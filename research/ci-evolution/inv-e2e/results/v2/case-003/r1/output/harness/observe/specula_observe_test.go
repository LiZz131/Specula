package state_test

// Specula code observation (case-003): drives ConsensusParams updates through the
// real BlockExecutor.ApplyBlock -> updateState path and prints the outcome without
// asserting a version-specific expectation, so the same file runs on the old
// (baseline) and updated trees. Self-contained: no instrumentation dependency.

import (
	"context"
	"fmt"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	dbm "github.com/cometbft/cometbft-db"
	abci "github.com/cometbft/cometbft/abci/types"
	cmtproto "github.com/cometbft/cometbft/api/cometbft/types/v1"
	"github.com/cometbft/cometbft/crypto/ed25519"
	sm "github.com/cometbft/cometbft/internal/state"
	"github.com/cometbft/cometbft/internal/store"
	"github.com/cometbft/cometbft/internal/test"
	"github.com/cometbft/cometbft/libs/log"
	mpmocks "github.com/cometbft/cometbft/mempool/mocks"
	"github.com/cometbft/cometbft/proxy"
	"github.com/cometbft/cometbft/types"
)

type obsApp struct {
	abci.BaseApplication
	updates map[int64]*cmtproto.ConsensusParams
}

func (a *obsApp) FinalizeBlock(_ context.Context, req *abci.FinalizeBlockRequest) (*abci.FinalizeBlockResponse, error) {
	txResults := make([]*abci.ExecTxResult, len(req.Txs))
	for i := range txResults {
		txResults[i] = &abci.ExecTxResult{Code: abci.CodeTypeOK}
	}
	return &abci.FinalizeBlockResponse{TxResults: txResults, ConsensusParamUpdates: a.updates[req.Height]}, nil
}

func obsRun(t *testing.T, name string, ve int64, n int64, updates map[int64]*cmtproto.ConsensusParams) {
	params := types.DefaultConsensusParams()
	params.ABCI.VoteExtensionsEnableHeight = ve
	pk := ed25519.GenPrivKeyFromSecret([]byte("specula-obs"))
	addr := pk.PubKey().Address()
	state, err := sm.MakeGenesisState(&types.GenesisDoc{
		ChainID: chainID, ConsensusParams: params,
		Validators: []types.GenesisValidator{{Address: addr, PubKey: pk.PubKey(), Power: 1000, Name: "v"}},
	})
	require.NoError(t, err)
	privVals := map[string]types.PrivValidator{addr.String(): types.NewMockPVWithParams(pk, false, false)}
	stateDB := dbm.NewMemDB()
	stateStore := sm.NewStore(stateDB, sm.StoreOptions{DiscardABCIResponses: false})
	require.NoError(t, stateStore.Save(state))
	blockStore := store.NewBlockStore(dbm.NewMemDB())
	proxyApp := proxy.NewAppConns(proxy.NewLocalClientCreator(&obsApp{updates: updates}), proxy.NopMetrics())
	require.NoError(t, proxyApp.Start())
	defer func() { _ = proxyApp.Stop() }()
	mp := &mpmocks.Mempool{}
	mp.On("Lock").Return()
	mp.On("Unlock").Return()
	mp.On("FlushAppConn", mock.Anything).Return(nil)
	mp.On("Update", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil)
	blockExec := sm.NewBlockExecutor(stateStore, log.NewNopLogger(), proxyApp.Consensus(), mp, sm.EmptyEvidencePool{}, blockStore)
	lastCommit := new(types.Commit)
	for h := int64(1); h <= n; h++ {
		block := state.MakeBlock(h, test.MakeNTxs(h, 2), lastCommit, nil, state.Validators.GetProposer().Address)
		parts, err := block.MakePartSet(testPartSize)
		require.NoError(t, err)
		blockID := types.BlockID{Hash: block.Hash(), PartSetHeader: parts.Header()}
		ec, err := makeValidCommit(h, blockID, state.Validators, privVals)
		require.NoError(t, err)
		blockStore.SaveBlock(block, parts, ec.ToCommit())
		pre := state.ConsensusParams.ABCI.VoteExtensionsEnableHeight
		next, err := blockExec.ApplyBlock(state, blockID, block)
		if err != nil {
			fmt.Printf("SPECULA-OBS scenario=%s height=%d current_ve=%d result=REJECTED err=%q\n", name, h, pre, err.Error())
			return
		}
		state = next
		lastCommit = ec.ToCommit()
	}
	fmt.Printf("SPECULA-OBS scenario=%s height=%d final_ve=%d result=ACCEPTED_ALL\n", name, n, state.ConsensusParams.ABCI.VoteExtensionsEnableHeight)
}

func obsAbci(ve int64) *cmtproto.ConsensusParams {
	return &cmtproto.ConsensusParams{Abci: &cmtproto.ABCIParams{VoteExtensionsEnableHeight: ve}}
}

func obsFull(ve, maxBytes int64) *cmtproto.ConsensusParams {
	p := types.DefaultConsensusParams()
	p.ABCI.VoteExtensionsEnableHeight = ve
	p.Block.MaxBytes = maxBytes
	pb := p.ToProto()
	return &pb
}

func TestSpeculaObserveValidateUpdate(t *testing.T) {
	def := types.DefaultConsensusParams().Block.MaxBytes
	obsRun(t, "O1_enable_from_0_at_h_plus_1", 0, 1, map[int64]*cmtproto.ConsensusParams{1: obsAbci(2)})
	obsRun(t, "O2_cancel_scheduled", 5, 1, map[int64]*cmtproto.ConsensusParams{1: obsAbci(0)})
	obsRun(t, "O3_unchanged_after_enable_abci_only", 1, 2, map[int64]*cmtproto.ConsensusParams{2: obsAbci(1)})
	obsRun(t, "O4_unchanged_before_enable", 5, 1, map[int64]*cmtproto.ConsensusParams{1: obsAbci(5)})
	obsRun(t, "O5_modify_scheduled", 5, 1, map[int64]*cmtproto.ConsensusParams{1: obsAbci(7)})
	obsRun(t, "O6_disable_after_enable", 1, 1, map[int64]*cmtproto.ConsensusParams{1: obsAbci(0)})
	obsRun(t, "O7_modify_after_enable", 1, 1, map[int64]*cmtproto.ConsensusParams{1: obsAbci(5)})
	obsRun(t, "O8_enable_at_current_height", 0, 2, map[int64]*cmtproto.ConsensusParams{2: obsAbci(2)})
	obsRun(t, "O9_negative", 0, 1, map[int64]*cmtproto.ConsensusParams{1: obsAbci(-1)})
	obsRun(t, "O10_full_params_ve0_every_block", 0, 3, map[int64]*cmtproto.ConsensusParams{
		1: obsFull(0, def+1), 2: obsFull(0, def+2), 3: obsFull(0, def+3)})
	obsRun(t, "O11_full_params_ve_enabled_every_block", 1, 3, map[int64]*cmtproto.ConsensusParams{
		1: obsFull(1, def+1), 2: obsFull(1, def+2), 3: obsFull(1, def+3)})
	obsRun(t, "O12_enable_then_full_params_after_reached", 0, 4, map[int64]*cmtproto.ConsensusParams{
		1: obsAbci(3), 4: obsFull(3, def+4)})
	obsRun(t, "O13_block_only_update_after_enable", 1, 2, map[int64]*cmtproto.ConsensusParams{
		2: {Block: &cmtproto.BlockParams{MaxBytes: def + 5, MaxGas: types.DefaultConsensusParams().Block.MaxGas}}})
}
