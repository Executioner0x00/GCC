// { dg-do run { target c++11 } }
// { dg-require-effective-target hosted }

// Copyright (C) 2005-2025 Free Software Foundation, Inc.
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

// You should have received a copy of the GNU General Public License along
// with this library; see the file COPYING3.  If not see
// <http://www.gnu.org/licenses/>.

// 20.6.6.2 Template class shared_ptr [util.smartptr.shared]

#include <memory>
#include <testsuite_hooks.h>

struct A { };

// 20.6.6.2.1 shared_ptr constructors [util.smartptr.shared.const]

// Construction from weak_ptr
int
test01()
{
  A * const a = new A;
  std::shared_ptr<A> a1(a);
  std::weak_ptr<A> wa(a1);
  std::shared_ptr<A> a2(wa);
  VERIFY( a2.get() == a );
  VERIFY( a2.use_count() == wa.use_count() );

  return 0;
}


int
main()
{
  test01();
  return 0;
}
