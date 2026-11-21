package state_test

// MC-1 reproduction (case-003). Self-contained; drop into internal/state of a
// CometBFT tree. It applies real blocks through BlockExecutor.ApplyBlock with an
// application that returns its complete consensus params (ConsensusParams.ToProto,
// which always includes the Abci subrecord) whenever it changes a parameter.
// Vote extensions are enabled from height 1 (genesis), so every such update
// re-sends the unchanged, already reached VoteExtensionsEnableHeight.
//
// Expected (protocol: the enable height is not changed; each non-empty field is
// applied in full): every block is applied.  Observed on the updated revision:
// ApplyBlock fails with "vote extensions cannot be updated to a past or current
// height", which consensus treats as fatal (chain halt).

import (
	"context"
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

type mc1App struct {
	abci.BaseApplication
	updates map[int64]*cmtproto.ConsensusParams
}

func (a *mc1App) FinalizeBlock(_ context.Context, req *abci.FinalizeBlockRequest) (*abci.FinalizeBlockResponse, error) {
	res := make([]*abci.ExecTxResult, len(req.Txs))
	for i := range res {
		res[i] = &abci.ExecTxResult{Code: abci.CodeTypeOK}
	}
	return &abci.FinalizeBlockResponse{TxResults: res, ConsensusParamUpdates: a.updates[req.Height]}, nil
}

func mc1Apply(t *testing.T, genesisVE int64, n int64, updates map[int64]*cmtproto.ConsensusParams) (int64, error) {
	t.Helper()
	params := types.DefaultConsensusParams()
	params.ABCI.VoteExtensionsEnableHeight = genesisVE
	pk := ed25519.GenPrivKeyFromSecret([]byte("specula-mc1"))
	addr := pk.PubKey().Address()
	state, err := sm.MakeGenesisState(&types.GenesisDoc{
		ChainID: chainID, ConsensusParams: params,
		Validators: []types.GenesisValidator{{Address: addr, PubKey: pk.PubKey(), Power: 1000, Name: "v"}},
	})
	require.NoError(t, err)
	privVals := map[string]types.PrivValidator{addr.String(): types.NewMockPVWithParams(pk, false, false)}
	stateStore := sm.NewStore(dbm.NewMemDB(), sm.StoreOptions{DiscardABCIResponses: false})
	require.NoError(t, stateStore.Save(state))
	blockStore := store.NewBlockStore(dbm.NewMemDB())
	proxyApp := proxy.NewAppConns(proxy.NewLocalClientCreator(&mc1App{updates: updates}), proxy.NopMetrics())
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
		next, err := blockExec.ApplyBlock(state, blockID, block)
		if err != nil {
			return h, err
		}
		state = next
		lastCommit = ec.ToCommit()
	}
	return n, nil
}

func mc1Complete(ve, maxBytes int64) *cmtproto.ConsensusParams {
	p := types.DefaultConsensusParams()
	p.ABCI.VoteExtensionsEnableHeight = ve
	p.Block.MaxBytes = maxBytes
	pb := p.ToProto()
	return &pb
}

// TestSpeculaMC1UnchangedEnableHeightNotRejected: complete-params updates after
// the enable height is reached must not halt block application.
func TestSpeculaMC1UnchangedEnableHeightNotRejected(t *testing.T) {
	def := types.DefaultConsensusParams().Block.MaxBytes
	h, err := mc1Apply(t, 1, 3, map[int64]*cmtproto.ConsensusParams{
		1: mc1Complete(1, def+1),
		2: mc1Complete(1, def+2),
		3: mc1Complete(1, def+3),
	})
	require.NoError(t, err, "ApplyBlock failed at height %d", h)
}

// TestSpeculaMC1UnchangedAbciOnlyNotRejected: the minimal trigger, an Abci
// subrecord repeating the reached enable height (no other change).
func TestSpeculaMC1UnchangedAbciOnlyNotRejected(t *testing.T) {
	h, err := mc1Apply(t, 1, 2, map[int64]*cmtproto.ConsensusParams{
		2: {Abci: &cmtproto.ABCIParams{VoteExtensionsEnableHeight: 1}},
	})
	require.NoError(t, err, "ApplyBlock failed at height %d", h)
}
