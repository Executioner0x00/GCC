// 2004-12-16  Paolo Carlini  <pcarlini@suse.de>
//
// Copyright (C) 2004-2025 Free Software Foundation, Inc.
//
// This file is part of the GNU ISO C++ Library.  This library is free
// software; you can redistribute it and/or modify it under the
// terms of the GNU General Public License as published by the
// Free Software Foundation; either version 3, or (at your option)
// any later version.
//
// This library is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along
// with this library; see the file COPYING3.  If not see
// <http://www.gnu.org/licenses/>.

// 4.7.1 Const-volatile modifications

#include <tr1/type_traits>
#include <testsuite_hooks.h>
#include <testsuite_tr1.h>

void test01()
{
  using std::tr1::add_cv;
  using std::tr1::is_same;
  using namespace __gnu_test;

  VERIFY( (is_same<add_cv<int>::type, const volatile int>::value) );
  VERIFY( (is_same<add_cv<const int>::type, const volatile int>::value) );
  VERIFY( (is_same<add_cv<int*>::type, int* const volatile>::value) );
  VERIFY( (is_same<add_cv<int&>::type, int&>::value) );
  VERIFY( (is_same<add_cv<int (int)>::type, int (int)>::value) );
  VERIFY( (is_same<add_cv<const volatile int>::type,
	   const volatile int>::value) );
  VERIFY( (is_same<add_cv<ClassType>::type, const volatile ClassType>::value) );
  VERIFY( (is_same<add_cv<volatile ClassType>::type,
	   const volatile ClassType>::value) );
  VERIFY( (is_same<add_cv<ClassType*>::type,
	   ClassType* const volatile>::value) );
  VERIFY( (is_same<add_cv<ClassType&>::type, ClassType&>::value) );
  VERIFY( (is_same<add_cv<ClassType (ClassType)>::type,
	   ClassType (ClassType)>::value) );
  VERIFY( (is_same<add_cv<const volatile ClassType>::type,
	   const volatile ClassType>::value) );
}

int main()
{
  test01();
  return 0;
}
