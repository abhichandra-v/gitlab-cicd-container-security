// Package handlers implements the HTTP API.
package handlers

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"github.com/abhichandra-v/orders-api-pipeline/internal/store"
)

const (
	maxBodyBytes = 1 << 20
	maxFieldLen  = 200
	maxQuantity  = 10000
)

// OrderStore is the storage the handlers need.
type OrderStore interface {
	Create(customer, item string, quantity int) (store.Order, error)
	Get(id string) (store.Order, error)
	List() []store.Order
}

type createOrderRequest struct {
	Customer string `json:"customer"`
	Item     string `json:"item"`
	Quantity int    `json:"quantity"`
}

func (r createOrderRequest) validate() string {
	switch {
	case strings.TrimSpace(r.Customer) == "":
		return "customer is required"
	case len(r.Customer) > maxFieldLen:
		return "customer is too long"
	case strings.TrimSpace(r.Item) == "":
		return "item is required"
	case len(r.Item) > maxFieldLen:
		return "item is too long"
	case r.Quantity < 1 || r.Quantity > maxQuantity:
		return "quantity must be between 1 and 10000"
	}
	return ""
}

type api struct {
	store OrderStore
	log   *slog.Logger
}

func (a *api) createOrder(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()

	var req createOrderRequest
	if err := dec.Decode(&req); err != nil {
		var tooBig *http.MaxBytesError
		if errors.As(err, &tooBig) {
			writeError(w, http.StatusRequestEntityTooLarge, "request body too large")
			return
		}
		writeError(w, http.StatusBadRequest, "invalid JSON body")
		return
	}
	if msg := req.validate(); msg != "" {
		writeError(w, http.StatusUnprocessableEntity, msg)
		return
	}

	o, err := a.store.Create(strings.TrimSpace(req.Customer), strings.TrimSpace(req.Item), req.Quantity)
	switch {
	case errors.Is(err, store.ErrFull):
		writeError(w, http.StatusInsufficientStorage, "order store is full")
		return
	case err != nil:
		a.log.Error("create order failed", "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}

	w.Header().Set("Location", "/orders/"+o.ID)
	writeJSON(w, http.StatusCreated, o)
}

func (a *api) listOrders(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, a.store.List())
}

func (a *api) getOrder(w http.ResponseWriter, r *http.Request) {
	o, err := a.store.Get(r.PathValue("id"))
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, "order not found")
		return
	}
	if err != nil {
		a.log.Error("get order failed", "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}
	writeJSON(w, http.StatusOK, o)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}
