import Foundation

struct pthread_mutex_t { var lock: NSLock? }
func pthread_mutex_init(_ mutex: inout pthread_mutex_t, _ attributes: UnsafeRawPointer?) { mutex.lock = NSLock() }
func pthread_mutex_destroy(_ mutex: inout pthread_mutex_t) { mutex.lock = nil }
func pthread_mutex_lock(_ mutex: inout pthread_mutex_t) { mutex.lock!.lock() }
func pthread_mutex_unlock(_ mutex: inout pthread_mutex_t) { mutex.lock!.unlock() }
func pthread_mutex_trylock(_ mutex: inout pthread_mutex_t) -> Int32 { mutex.lock!.try() ? 0 : 1 }
