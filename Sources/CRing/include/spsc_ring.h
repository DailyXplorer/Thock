#ifndef THOCK_SPSC_RING_H
#define THOCK_SPSC_RING_H

#include <stdatomic.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define THOCK_RING_SLOT_SIZE 32
#define THOCK_RING_CACHE_LINE 64

typedef struct {
    _Alignas(THOCK_RING_CACHE_LINE) _Atomic(size_t) head;
    _Alignas(THOCK_RING_CACHE_LINE) _Atomic(size_t) tail;
    _Alignas(THOCK_RING_CACHE_LINE) _Atomic(uint64_t) dropped;
    size_t capacity;
    size_t mask;
    _Alignas(THOCK_RING_CACHE_LINE) unsigned char slots[];
} thock_ring;

static inline void *thock_ring_create(size_t capacity) {
    if (capacity < 2 || (capacity & (capacity - 1)) != 0) return NULL;
    size_t bytes = sizeof(thock_ring) + capacity * THOCK_RING_SLOT_SIZE;
    bytes = (bytes + THOCK_RING_CACHE_LINE - 1) & ~(size_t)(THOCK_RING_CACHE_LINE - 1);
    thock_ring *ring = (thock_ring *)aligned_alloc(THOCK_RING_CACHE_LINE, bytes);
    if (ring == NULL) return NULL;
    memset(ring, 0, bytes);
    atomic_init(&ring->head, 0);
    atomic_init(&ring->tail, 0);
    atomic_init(&ring->dropped, 0);
    ring->capacity = capacity;
    ring->mask = capacity - 1;
    return ring;
}

static inline void thock_ring_destroy(void *ring) {
    free(ring);
}

static inline size_t thock_ring_capacity(const void *ring) {
    return ((const thock_ring *)ring)->capacity;
}

static inline bool thock_ring_push(void *ring_ptr, const void *element, size_t size) {
    thock_ring *ring = (thock_ring *)ring_ptr;
    if (size > THOCK_RING_SLOT_SIZE) return false;
    size_t head = atomic_load_explicit(&ring->head, memory_order_relaxed);
    size_t tail = atomic_load_explicit(&ring->tail, memory_order_acquire);
    if (head - tail == ring->capacity) {
        atomic_fetch_add_explicit(&ring->dropped, 1, memory_order_relaxed);
        return false;
    }
    memcpy(ring->slots + (head & ring->mask) * THOCK_RING_SLOT_SIZE, element, size);
    atomic_store_explicit(&ring->head, head + 1, memory_order_release);
    return true;
}

static inline bool thock_ring_pop(void *ring_ptr, void *out, size_t size) {
    thock_ring *ring = (thock_ring *)ring_ptr;
    if (size > THOCK_RING_SLOT_SIZE) return false;
    size_t tail = atomic_load_explicit(&ring->tail, memory_order_relaxed);
    size_t head = atomic_load_explicit(&ring->head, memory_order_acquire);
    if (tail == head) return false;
    memcpy(out, ring->slots + (tail & ring->mask) * THOCK_RING_SLOT_SIZE, size);
    atomic_store_explicit(&ring->tail, tail + 1, memory_order_release);
    return true;
}

static inline uint64_t thock_ring_dropped(const void *ring_ptr) {
    thock_ring *ring = (thock_ring *)ring_ptr;
    return atomic_load_explicit(&ring->dropped, memory_order_relaxed);
}

#endif
