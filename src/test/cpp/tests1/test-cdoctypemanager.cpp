/*
	Copyright (C) 2021-2022, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/

#include "pch.h"
#include <windows.h>
#include <string>
#include "mem/CNativeW.h"
#include "env/CDocTypeManager.h"

TEST(CDocTypeManager, ConvertTypesExtToDlgExtNullptr1)
{
	const sakura::wstring expected = { LTEXT("") };
	sakura::wstring actual = CDocTypeManager::ConvertTypesExtToDlgExt(nullptr, nullptr);
	EXPECT_EQ(expected, actual);
}

TEST(CDocTypeManager, ConvertTypesExtToDlgExtNullptr2)
{
	const sakura::wstring expected = { LTEXT("") };
	sakura::wstring actual = CDocTypeManager::ConvertTypesExtToDlgExt(nullptr, LTEXT(".txt"));
	EXPECT_EQ(expected, actual);
}

TEST(CDocTypeManager, ConvertTypesExtToDlgExtOnce)
{
	const sakura::wstring expected = { LTEXT("*.txt;*.cpp") };
	sakura::wstring actual = CDocTypeManager::ConvertTypesExtToDlgExt(LTEXT("cpp"), LTEXT(".txt"));
	EXPECT_EQ(expected, actual);
}

TEST(CDocTypeManager, ConvertTypesExtToDlgExtTwo)
{
	const sakura::wstring expected = { LTEXT("*.txt;*.cpp;*.h") };
	sakura::wstring actual = CDocTypeManager::ConvertTypesExtToDlgExt(LTEXT("cpp;h"), LTEXT(".txt"));
	EXPECT_EQ(expected, actual);
}

TEST(CDocTypeManager, ConvertTypesExtToDlgExtThree)
{
	const sakura::wstring expected = { LTEXT("*.txt;*.cpp;*.h;*.hpp") };
	sakura::wstring actual = CDocTypeManager::ConvertTypesExtToDlgExt(LTEXT("cpp;h;hpp"), LTEXT(".txt"));
	EXPECT_EQ(expected, actual);
}

TEST(CDocTypeManager, ConvertTypesExtToDlgExtAppendPeriod)
{
	const sakura::wstring expected = { LTEXT("*.txt;*.cpp;*.h") };
	sakura::wstring actual = CDocTypeManager::ConvertTypesExtToDlgExt(LTEXT(".cpp;.h"), LTEXT(".txt"));
	EXPECT_EQ(expected, actual);
}

TEST(CDocTypeManager, ConvertTypesExtToDlgExtSeparatorSpace)
{
	const sakura::wstring expected = { LTEXT("*.txt;*.cpp;*.h") };
	sakura::wstring actual = CDocTypeManager::ConvertTypesExtToDlgExt(LTEXT("cpp h"), LTEXT(".txt"));
	EXPECT_EQ(expected, actual);
}

TEST(CDocTypeManager, ConvertTypesExtToDlgExtSeparatorComma)
{
	const sakura::wstring expected = { LTEXT("*.txt;*.cpp;*.h") } ;
	sakura::wstring actual = CDocTypeManager::ConvertTypesExtToDlgExt(LTEXT("cpp,h"), LTEXT(".txt"));
	EXPECT_EQ(expected, actual);
}

TEST(CDocTypeManager, ConvertTypesExtToDlgExtTopNullptr)
{
	const sakura::wstring expected = { LTEXT("*.cpp;*.h") };
	sakura::wstring actual = CDocTypeManager::ConvertTypesExtToDlgExt(LTEXT("cpp,h"), nullptr);
	EXPECT_EQ(expected, actual);
}

TEST(CDocTypeManager, ConvertTypesExtToDlgExtMerge)
{
	const sakura::wstring expected = { LTEXT("*.txt;*.cpp;*.h") };
	sakura::wstring actual = CDocTypeManager::ConvertTypesExtToDlgExt(LTEXT("txt,cpp,h"), LTEXT(".txt"));
	EXPECT_EQ(expected, actual);
}

TEST(CDocTypeManager, ConvertTypesExtToDlgExtMerge2)
{
	const sakura::wstring expected = { LTEXT("*.txt;*.cpp;*.h") };
	sakura::wstring actual = CDocTypeManager::ConvertTypesExtToDlgExt(LTEXT("cpp,h,txt"), LTEXT(".txt"));
	EXPECT_EQ(expected, actual);
}

TEST(CDocTypeManager, ConvertTypesExtToDlgExtExts64)
{
	const sakura::wstring expected = { LTEXT("*.txt;*.a;*.b;*.c;*.d;*.e;*.f;*.g;*.h;*.i;*.j;*.k;*.l;*.m;*.n;*.o;*.p;*.q;*.r;*.s;*.t;*.u;*.v;*.w;*.x;*.y;*.z;*.1;*.2;*.3;*.4;*.5;*.6") };
	sakura::wstring actual = CDocTypeManager::ConvertTypesExtToDlgExt(LTEXT("a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,y,z,1,2,3,4,5,6"), LTEXT(".txt"));
	EXPECT_EQ(expected, actual);
}

TEST(CDocTypeManager, ConvertTypesExtToDlgExtExts64LongFileExt)
{
	const sakura::wstring expected = { LTEXT("*.extension_260_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long;*.a;*.b;*.c;*.d;*.e;*.f;*.g;*.h;*.i;*.j;*.k;*.l;*.m;*.n;*.o;*.p;*.q;*.r;*.s;*.t;*.u;*.v;*.w;*.x;*.y;*.z;*.1;*.2;*.3;*.4;*.5;*.6") };
	sakura::wstring actual = CDocTypeManager::ConvertTypesExtToDlgExt(LTEXT("a,b,c,d,e,f,g,h,i,j,k,l,m,n,o,p,q,r,s,t,u,v,w,x,y,z,1,2,3,4,5,6"), LTEXT(".extension_260_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long_long"));
	EXPECT_EQ(expected, actual);
}
