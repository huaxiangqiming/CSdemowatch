package demo

import "math"

// SampleGate selects existing source snapshots, never invents intermediate ticks.
// Gaps advance the next deadline in one step, rather than duplicating state.
type SampleGate struct {
	Rate float64
	next float64
}

func (g *SampleGate) Due(seconds float64) bool {
	if seconds+1e-9 < g.next {
		return false
	}
	g.next = (math.Floor(seconds*g.Rate+1e-9) + 1) / g.Rate
	return true
}
