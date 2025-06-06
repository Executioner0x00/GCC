// -*- C++ -*- header.

// Copyright (C) 2020-2025 Free Software Foundation, Inc.
//
// This file is part of the GNU ISO C++ Library.  This library is free
// software; you can redistribute it and/or modify it under the
// terms of the GNU General Public License as published by the
// Free Software Foundation; either version 3, or (at your option)
// any later version.

// This library is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// Under Section 7 of GPL version 3, you are granted additional
// permissions described in the GCC Runtime Library Exception, version
// 3.1, as published by the Free Software Foundation.

// You should have received a copy of the GNU General Public License and
// a copy of the GCC Runtime Library Exception along with this program;
// see the files COPYING3 and COPYING.RUNTIME respectively.  If not, see
// <http://www.gnu.org/licenses/>.

/** @file bits/semaphore_base.h
 *  This is an internal header file, included by other library headers.
 *  Do not attempt to use it directly. @headername{semaphore}
 */

#ifndef _GLIBCXX_SEMAPHORE_BASE_H
#define _GLIBCXX_SEMAPHORE_BASE_H 1

#ifdef _GLIBCXX_SYSHDR
#pragma GCC system_header
#endif

#include <bits/version.h>

#ifdef __glibcxx_semaphore // C++ >= 20 && hosted && atomic_wait
#include <bits/atomic_base.h>
#include <bits/chrono.h>
#include <bits/atomic_timed_wait.h>
#include <ext/numeric_traits.h>

namespace std _GLIBCXX_VISIBILITY(default)
{
_GLIBCXX_BEGIN_NAMESPACE_VERSION

  template<bool _Platform_wait>
  struct __semaphore_base
  {
    using __count_type = __conditional_t<_Platform_wait,
					 __detail::__platform_wait_t,
					 ptrdiff_t>;

    static constexpr ptrdiff_t _S_max
      = __gnu_cxx::__int_traits<__count_type>::__max;

    constexpr explicit
    __semaphore_base(__count_type __count) noexcept
    : _M_counter(__count)
    { }

    __semaphore_base(const __semaphore_base&) = delete;
    __semaphore_base& operator=(const __semaphore_base&) = delete;

    // Load the current counter value.
    _GLIBCXX_ALWAYS_INLINE __count_type
    _M_get_current() const noexcept
    { return __atomic_impl::load(&_M_counter, memory_order::acquire); }

    // Try to acquire the semaphore (i.e. decrement the counter).
    // Returns false if the current counter is zero, or if another thread
    // decrements the value first. In the latter case, __cur is set to the
    // new value.
    _GLIBCXX_ALWAYS_INLINE bool
    _M_do_try_acquire(__count_type& __cur) noexcept
    {
      if (__cur == 0)
	return false; // Cannot decrement when it's already zero.

      return __atomic_impl::compare_exchange_strong(&_M_counter,
						    __cur, __cur - 1,
						    memory_order::acquire,
						    memory_order::relaxed);
    }

    void
    _M_acquire() noexcept
    {
      auto const __vfn = [this]{ return _M_get_current(); };
      auto __val = __vfn();
      auto const __pred = [&__val](__count_type __cur) {
	if (__cur > 0)
	  {
	    __val = __cur;
	    return true;
	  }
	return false;
      };
      while (!_M_do_try_acquire(__val))
	if (__val == 0)
	  std::__atomic_wait_address(&_M_counter, __pred, __vfn, true);
    }

    bool
    _M_try_acquire() noexcept
    {
      // The fastest implementation of this function is just _M_do_try_acquire
      // but that can fail under contention even when _M_count > 0.
      // Using _M_try_acquire_for(0ns) will retry a few times in a loop.
      return _M_try_acquire_for(__detail::__wait_clock_t::duration{});
    }

    template<typename _Clock, typename _Duration>
      bool
      _M_try_acquire_until(const chrono::time_point<_Clock, _Duration>& __atime) noexcept
      {
	auto const __vfn = [this]{ return _M_get_current(); };
	auto __val = __vfn();
	auto const __pred = [&__val](__count_type __cur) {
	  if (__cur > 0)
	    {
	      __val = __cur;
	      return true;
	    }
	  return false;
	};
	while (!_M_do_try_acquire(__val))
	  if (__val == 0)
	    {
	      if (!std::__atomic_wait_address_until(&_M_counter, __pred,
						    __vfn, __atime, true))
		return false; // timed out
	    }
	return true;
      }

    template<typename _Rep, typename _Period>
      bool
      _M_try_acquire_for(const chrono::duration<_Rep, _Period>& __rtime) noexcept
      {
	auto const __vfn = [this]{ return _M_get_current(); };
	auto __val = __vfn();
	auto const __pred = [&__val](__count_type __cur) {
	  if (__cur > 0)
	    {
	      __val = __cur;
	      return true;
	    }
	  return false;
	};
	while (!_M_do_try_acquire(__val))
	  if (__val == 0)
	    {
	      if (!std::__atomic_wait_address_for(&_M_counter, __pred,
						  __vfn, __rtime, true))
		return false; // timed out
	    }
	return true;
      }

    _GLIBCXX_ALWAYS_INLINE ptrdiff_t
    _M_release(ptrdiff_t __update) noexcept
    {
      auto __old = __atomic_impl::fetch_add(&_M_counter, __update,
					    memory_order::release);
      if (__old == 0 && __update > 0)
	__atomic_notify_address(&_M_counter, true, true);
      return __old;
    }

  private:
    alignas(_Platform_wait ? __detail::__platform_wait_alignment
			   : __alignof__(__count_type))
    __count_type _M_counter;
  };

  template<ptrdiff_t _Max>
    using __semaphore_impl
      = __semaphore_base<(_Max <= __semaphore_base<true>::_S_max)>;

_GLIBCXX_END_NAMESPACE_VERSION
} // namespace std
#endif // __glibcxx_semaphore
#endif // _GLIBCXX_SEMAPHORE_BASE_H
