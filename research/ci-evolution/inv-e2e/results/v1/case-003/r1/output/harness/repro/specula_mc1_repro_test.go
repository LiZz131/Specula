package state_test

// Specula MC-1 reproduction (instrumentation-free).
//
// A chain whose genesis enables vote extensions at its initial height (the
// set-up recommended by spec/abci/abci++_app_requirements.md "Application
// configuration required to switch to ABCI 2.0") runs an application that
// returns its complete, unchanged consensus parameters from FinalizeBlock
// (non-empty fields are applied in full; ToProto always sets Abci).
//
// Expected (contract): the unchanged update is accepted and the node keeps
// running; after a restart the handshake succeeds.
// Bug (MC-1): ValidateUpdate rejects the unchanged, already reached
// VoteExtensionsEnableHeight, ApplyBlock fails after the response is durable
// (production callers panic), and every restart replays the stored block and
// fails the same way.
//
// PASS = behaviour consistent with the contract; FAIL = MC-1 present.

import (
	"context"
	"testing"

	"github.com/stretchr/testify/mock"
	"github.com/stretchr/testify/require"

	dbm "github.com/cometbft/cometbft-db"
	abci "github.com/cometbft/cometbft/abci/types"
	cmtproto "github.com/cometbft/cometbft/api/cometbft/types/v1"
	"github.com/cometbft/cometbft/crypto/ed25519"
	"github.com/cometbft/cometbft/internal/consensus"
	sm "github.com/cometbft/cometbft/internal/state"
	"github.com/cometbft/cometbft/internal/store"
	"github.com/cometbft/cometbft/libs/log"
	mpmocks "github.com/cometbft/cometbft/mempool/mocks"
	"github.com/cometbft/cometbft/proxy"
	"github.com/cometbft/cometbft/types"
)

type mc1EchoApp struct {
	abci.BaseApplication
	echo      *cmtproto.ConsensusParams
	committed int64
}

func (a *mc1EchoApp) Info(context.Context, *abci.InfoRequest) (*abci.InfoResponse, error) {
	return &abci.InfoResponse{LastBlockHeight: a.committed}, nil
}

func (a *mc1EchoApp) FinalizeBlock(_ context.Context, req *abci.FinalizeBlockRequest) (*abci.FinalizeBlockResponse, error) {
	res := make([]*abci.ExecTxResult, len(req.Txs))
	for i := range res {
		res[i] = &abci.ExecTxResult{Code: abci.CodeTypeOK}
	}
	return &abci.FinalizeBlockResponse{TxResults: res, ConsensusParamUpdates: a.echo}, nil
}

func (a *mc1EchoApp) Commit(context.Context, *abci.CommitRequest) (*abci.CommitResponse, error) {
	a.committed++
	return &abci.CommitResponse{}, nil
}

func mc1Start(t *testing.T, app abci.Application) proxy.AppConns {
	t.Helper()
	conns := proxy.NewAppConns(proxy.NewLocalClientCreator(app), proxy.NopMetrics())
	require.NoError(t, conns.Start())
	t.Cleanup(func() { _ = conns.Stop() })
	return conns
}

func TestSpeculaMC1UnchangedVoteExtensionsEnableHeight(t *testing.T) {
	pk := ed25519.GenPrivKeyFromSecret([]byte("specula-mc1"))
	params := types.DefaultConsensusParams()
	params.ABCI.VoteExtensionsEnableHeight = 1 // = InitialHeight
	genDoc := &types.GenesisDoc{
		ChainID:         "specula-mc1",
		ConsensusParams: params,
		Validators: []types.GenesisValidator{{
			Address: pk.PubKey().Address(), PubKey: pk.PubKey(), Power: 10, Name: "v0",
		}},
	}
	state, err := sm.MakeGenesisState(genDoc)
	require.NoError(t, err)
	stateStore := sm.NewStore(dbm.NewMemDB(), sm.StoreOptions{DiscardABCIResponses: false})
	require.NoError(t, stateStore.Save(state))
	blockStore := store.NewBlockStore(dbm.NewMemDB())
	pb := state.ConsensusParams.ToProto() // complete, unchanged parameter set
	newApp := func() *mc1EchoApp { return &mc1EchoApp{echo: &pb} }

	// Node start: genesis handshake.
	conns := mc1Start(t, newApp())
	require.NoError(t, consensus.NewHandshaker(stateStore, state, blockStore, genDoc).
		Handshake(context.Background(), conns))
	state, err = stateStore.Load()
	require.NoError(t, err)

	// Height 1 is decided, stored, and applied (consensus/state.go finalizeCommit).
	mp := &mpmocks.Mempool{}
	mp.On("Lock").Return()
	mp.On("Unlock").Return()
	mp.On("FlushAppConn", mock.Anything).Return(nil)
	mp.On("Update", mock.Anything, mock.Anything, mock.Anything, mock.Anything, mock.Anything).Return(nil)
	blockExec := sm.NewBlockExecutor(stateStore, log.NewNopLogger(), conns.Consensus(), mp,
		sm.EmptyEvidencePool{}, blockStore)
	block := state.MakeBlock(1, nil, new(types.Commit), nil, state.Validators.GetProposer().Address)
	parts, err := block.MakePartSet(types.BlockPartSizeBytes)
	require.NoError(t, err)
	blockID := types.BlockID{Hash: block.Hash(), PartSetHeader: parts.Header()}
	blockStore.SaveBlock(block, parts, &types.Commit{Height: 1, BlockID: blockID})
	_, applyErr := blockExec.ApplyBlock(state, blockID, block)
	t.Logf("SPECULA_MC1 apply_error=%v", applyErr)

	// Restart with the application's durable state (nothing committed if
	// ApplyBlock failed; height 1 committed otherwise).
	restarted, err := stateStore.Load()
	require.NoError(t, err)
	app2 := newApp()
	if applyErr == nil {
		app2.committed = 1
	}
	handshakeErr := consensus.NewHandshaker(stateStore, restarted, blockStore, genDoc).
		Handshake(context.Background(), mc1Start(t, app2))
	t.Logf("SPECULA_MC1 restart_handshake_error=%v", handshakeErr)

	require.NoError(t, applyErr, "MC-1: unchanged VoteExtensionsEnableHeight rejected; production consensus panics here")
	require.NoError(t, handshakeErr, "MC-1: restart replay rejects the same block again (permanent halt)")
}
