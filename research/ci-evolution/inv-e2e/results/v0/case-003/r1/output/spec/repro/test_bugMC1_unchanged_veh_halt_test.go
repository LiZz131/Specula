package consensus

// Specula finding MC-1 reproduction (Level 0: real consensus node, real
// kvstore ABCI application, public ABCI response fields only).
//
// Copied into internal/consensus of an exported source tree by
// spec/repro/run_MC-1.sh; run once on the updated tree and once on the
// baseline (old) tree as a control.

import (
	"bytes"
	"context"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/cometbft/cometbft/abci/example/kvstore"
	abci "github.com/cometbft/cometbft/abci/types"
	cmtproto "github.com/cometbft/cometbft/api/cometbft/types/v1"
	"github.com/cometbft/cometbft/libs/log"
	"github.com/cometbft/cometbft/types"
)

type speculaSyncBuf struct {
	mu sync.Mutex
	b  bytes.Buffer
}

func (s *speculaSyncBuf) Write(p []byte) (int, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.b.Write(p)
}

func (s *speculaSyncBuf) String() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.b.String()
}

// paramsApp is the stock kvstore application that, at one height, returns a
// consensus-parameter update in FinalizeBlockResponse: a Block.MaxBytes change
// plus the Abci sub-record set to abciVEH.
type paramsApp struct {
	*kvstore.Application
	at      int64
	abciVEH int64
}

func (app *paramsApp) FinalizeBlock(ctx context.Context, req *abci.FinalizeBlockRequest) (*abci.FinalizeBlockResponse, error) {
	resp, err := app.Application.FinalizeBlock(ctx, req)
	if err == nil && req.Height == app.at {
		bp := types.DefaultBlockParams()
		resp.ConsensusParamUpdates = &cmtproto.ConsensusParams{
			Block: &cmtproto.BlockParams{MaxBytes: bp.MaxBytes + 1, MaxGas: bp.MaxGas},
			Abci:  &cmtproto.ABCIParams{VoteExtensionsEnableHeight: app.abciVEH},
		}
	}
	return resp, err
}

// runChain starts a one-validator consensus node and reports the highest
// committed height reached within the window, plus the captured log.
func runChain(t *testing.T, genesisVEH, at, abciVEH int64, want int64) (int64, string) {
	t.Helper()
	app := &paramsApp{Application: kvstore.NewInMemoryApplication(), at: at, abciVEH: abciVEH}
	cs, _ := randStateWithAppWithHeight(1, app, genesisVEH)
	buf := &speculaSyncBuf{}
	cs.SetLogger(log.NewTMLogger(log.NewSyncWriter(buf)))
	newBlockCh := subscribe(cs.eventBus, types.EventQueryNewBlock)
	startTestRound(cs, cs.Height, cs.Round)
	defer func() { _ = cs.Stop() }()

	var last int64
	deadline := time.After(15 * time.Second)
	for last < want {
		select {
		case msg := <-newBlockCh:
			last = msg.Data().(types.EventDataNewBlock).Block.Height
		case <-deadline:
			return last, buf.String()
		}
	}
	return last, buf.String()
}

func report(t *testing.T, name string, last, want int64, logs string) {
	t.Helper()
	failure := strings.Contains(logs, "CONSENSUS FAILURE")
	t.Logf("%s: highest committed height=%d (target %d); CONSENSUS FAILURE logged=%v", name, last, want, failure)
	for _, line := range strings.Split(logs, "\n") {
		if strings.Contains(line, "CONSENSUS FAILURE") {
			if i := strings.Index(line, "stack="); i > 0 {
				line = line[:i]
			}
			t.Logf("%s: %s", name, line)
		}
	}
	if last >= want && !failure {
		t.Logf("%s: OUTCOME=CHAIN_PROGRESSED", name)
	} else {
		t.Logf("%s: OUTCOME=CHAIN_HALTED", name)
	}
}

// MC-1 trigger: vote extensions enabled at genesis (height 1, the default of
// internal/test/params.go); at height 2 the application changes Block.MaxBytes
// and re-sends its UNCHANGED Abci sub-record (VoteExtensionsEnableHeight=1).
// Expected (contract): the chain keeps committing.
func TestSpeculaReproMC1UnchangedEnableHeight(t *testing.T) {
	last, logs := runChain(t, 1, 2, 1, 4)
	report(t, "MC-1 unchanged-after-enable", last, 4, logs)
}

// Control for the bug the update fixes: vote extensions disabled at genesis;
// at height 2 the application enables them at height 4 (> current height).
func TestSpeculaReproControlEnableFromZero(t *testing.T) {
	last, logs := runChain(t, 0, 2, 4, 5)
	report(t, "control enable-from-zero", last, 5, logs)
}
