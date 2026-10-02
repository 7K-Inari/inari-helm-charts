package poll

import (
	"errors"
	"testing"
	"time"
)

func TestUntilSucceedsImmediately(t *testing.T) {
	calls := 0
	err := Until(time.Second, 10*time.Millisecond, func() (bool, error) {
		calls++
		return true, nil
	})
	if err != nil {
		t.Fatalf("Until: %v", err)
	}
	if calls != 1 {
		t.Fatalf("cond called %d times, want 1", calls)
	}
}

func TestUntilSucceedsAfterRetries(t *testing.T) {
	calls := 0
	err := Until(5*time.Second, 10*time.Millisecond, func() (bool, error) {
		calls++
		return calls >= 3, nil
	})
	if err != nil {
		t.Fatalf("Until: %v", err)
	}
	if calls != 3 {
		t.Fatalf("cond called %d times, want 3", calls)
	}
}

func TestUntilAbortsOnError(t *testing.T) {
	boom := errors.New("boom")
	calls := 0
	err := Until(5*time.Second, 10*time.Millisecond, func() (bool, error) {
		calls++
		return false, boom
	})
	if !errors.Is(err, boom) {
		t.Fatalf("Until error = %v, want wrapped %v", err, boom)
	}
	if calls != 1 {
		t.Fatalf("cond called %d times, want 1 (error must abort)", calls)
	}
}

func TestUntilTimesOut(t *testing.T) {
	start := time.Now()
	err := Until(120*time.Millisecond, 20*time.Millisecond, func() (bool, error) {
		return false, nil
	})
	if err == nil {
		t.Fatal("Until succeeded, want timeout error")
	}
	if elapsed := time.Since(start); elapsed > 2*time.Second {
		t.Fatalf("Until ran %s, far over the 120ms timeout", elapsed)
	}
}
