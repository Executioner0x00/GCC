// { dg-do run { target c++17 } }

// Copyright (C) 2014-2025 Free Software Foundation, Inc.
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

#include <any>
#include <testsuite_hooks.h>

using std::any;

void test01()
{
  any x;
  any y;
  y = x;
  VERIFY( !x.has_value() );
  VERIFY( !y.has_value() );

  y = std::move(x);
  VERIFY( !x.has_value() );
  VERIFY( !y.has_value() );
}

void test02()
{
  any x(1);
  any y;
  y = x;
  VERIFY( x.has_value() );
  VERIFY( y.has_value() );

  x = std::move(y);
  VERIFY( x.has_value() );
  VERIFY( !y.has_value() );

  x = y;
  VERIFY( !x.has_value() );
  VERIFY( !y.has_value() );
}

int main()
{
  test01();
  test02();
}
