// Package store holds orders in memory.
package store

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"sort"
	"sync"
	"time"
)

// Errors returned by Store.
var (
	ErrNotFound = errors.New("order not found")
	ErrFull     = errors.New("order store is full")
)

// Order is a single customer order.
type Order struct {
	ID        string    `json:"id"`
	Customer  string    `json:"customer"`
	Item      string    `json:"item"`
	Quantity  int       `json:"quantity"`
	CreatedAt time.Time `json:"created_at"`
}

// Store is a concurrency-safe in-memory order store with a fixed capacity,
// so a client cannot grow the process without bound.
type Store struct {
	mu     sync.RWMutex
	orders map[string]Order
	max    int
	now    func() time.Time
	newID  func() (string, error)
}

// New returns a Store that holds at most max orders.
func New(max int) *Store {
	return &Store{
		orders: make(map[string]Order),
		max:    max,
		now:    func() time.Time { return time.Now().UTC() },
		newID:  randomID,
	}
}

func randomID() (string, error) {
	b := make([]byte, 8)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

// Create stores a new order and returns it with its ID and creation time set.
func (s *Store) Create(customer, item string, quantity int) (Order, error) {
	id, err := s.newID()
	if err != nil {
		return Order{}, err
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	if len(s.orders) >= s.max {
		return Order{}, ErrFull
	}
	o := Order{ID: id, Customer: customer, Item: item, Quantity: quantity, CreatedAt: s.now()}
	s.orders[id] = o
	return o, nil
}

// Get returns the order with the given ID.
func (s *Store) Get(id string) (Order, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	o, ok := s.orders[id]
	if !ok {
		return Order{}, ErrNotFound
	}
	return o, nil
}

// List returns all orders, oldest first.
func (s *Store) List() []Order {
	s.mu.RLock()
	defer s.mu.RUnlock()

	out := make([]Order, 0, len(s.orders))
	for _, o := range s.orders {
		out = append(out, o)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].CreatedAt.Equal(out[j].CreatedAt) {
			return out[i].ID < out[j].ID
		}
		return out[i].CreatedAt.Before(out[j].CreatedAt)
	})
	return out
}
