package store

import (
	"errors"
	"fmt"
	"sync"
	"testing"
	"time"
)

func TestCreateAndGet(t *testing.T) {
	s := New(10)

	created, err := s.Create("alice", "widget", 2)
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	if len(created.ID) != 16 {
		t.Errorf("ID = %q, want 16 hex characters", created.ID)
	}
	if created.CreatedAt.IsZero() || created.CreatedAt.Location() != time.UTC {
		t.Errorf("CreatedAt = %v, want non-zero UTC time", created.CreatedAt)
	}

	got, err := s.Get(created.ID)
	if err != nil {
		t.Fatalf("Get: %v", err)
	}
	if got != created {
		t.Errorf("Get = %+v, want %+v", got, created)
	}
}

func TestGet(t *testing.T) {
	s := New(10)
	o, err := s.Create("alice", "widget", 1)
	if err != nil {
		t.Fatalf("Create: %v", err)
	}

	tests := []struct {
		name    string
		id      string
		wantErr error
	}{
		{"existing", o.ID, nil},
		{"unknown", "does-not-exist", ErrNotFound},
		{"empty", "", ErrNotFound},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := s.Get(tt.id)
			if !errors.Is(err, tt.wantErr) {
				t.Errorf("Get(%q) error = %v, want %v", tt.id, err, tt.wantErr)
			}
		})
	}
}

func TestCreateRespectsCapacity(t *testing.T) {
	tests := []struct {
		name    string
		max     int
		creates int
		wantErr error
	}{
		{"below capacity", 3, 2, nil},
		{"at capacity", 3, 3, nil},
		{"over capacity", 3, 4, ErrFull},
		{"zero capacity", 0, 1, ErrFull},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			s := New(tt.max)
			var err error
			for i := 0; i < tt.creates; i++ {
				_, err = s.Create("c", "i", 1)
			}
			if !errors.Is(err, tt.wantErr) {
				t.Errorf("last Create error = %v, want %v", err, tt.wantErr)
			}
			if got := len(s.List()); got > tt.max {
				t.Errorf("store holds %d orders, capacity is %d", got, tt.max)
			}
		})
	}
}

func TestCreateReturnsIDError(t *testing.T) {
	s := New(10)
	want := errors.New("no entropy")
	s.newID = func() (string, error) { return "", want }

	if _, err := s.Create("c", "i", 1); !errors.Is(err, want) {
		t.Errorf("Create error = %v, want %v", err, want)
	}
	if len(s.List()) != 0 {
		t.Error("an order was stored despite the ID error")
	}
}

func TestListIsOrderedOldestFirst(t *testing.T) {
	s := New(10)
	base := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)

	// Insert out of order: timestamps 2, 0, 1, then two that tie at 3.
	stamps := []int{2, 0, 1, 3, 3}
	ids := []string{"c", "a", "b", "e", "d"}
	for i := range stamps {
		s.now = func() time.Time { return base.Add(time.Duration(stamps[i]) * time.Second) }
		s.newID = func() (string, error) { return ids[i], nil }
		if _, err := s.Create("c", "i", 1); err != nil {
			t.Fatalf("Create: %v", err)
		}
	}

	var got string
	for _, o := range s.List() {
		got += o.ID
	}
	if want := "abcde"; got != want {
		t.Errorf("List order = %q, want %q", got, want)
	}
}

func TestListEmptyIsNotNil(t *testing.T) {
	if got := New(1).List(); got == nil {
		t.Error("List on an empty store returned nil, want empty slice")
	}
}

func TestConcurrentUse(t *testing.T) {
	const workers, perWorker = 8, 50
	s := New(workers * perWorker)

	var wg sync.WaitGroup
	errs := make(chan error, workers*perWorker)
	for w := 0; w < workers; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for i := 0; i < perWorker; i++ {
				o, err := s.Create("c", "i", 1)
				if err != nil {
					errs <- fmt.Errorf("Create: %w", err)
					return
				}
				if _, err := s.Get(o.ID); err != nil {
					errs <- fmt.Errorf("Get: %w", err)
					return
				}
				s.List()
			}
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Error(err)
	}

	if got := len(s.List()); got != workers*perWorker {
		t.Errorf("stored %d orders, want %d", got, workers*perWorker)
	}
}
