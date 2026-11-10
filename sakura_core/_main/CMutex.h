/*!	@file
	@brief Mutex管理

	@author ryoji
	@date 2007.07.05
*/
/*
	Copyright (C) 2007, ryoji, genta
	Copyright (C) 2018-2022, Sakura Editor Organization

	SPDX-License-Identifier: Zlib
*/

#ifndef SAKURA_CMUTEX_51EDDE78_F635_419A_9E10_159485D0F710_H_
#define SAKURA_CMUTEX_51EDDE78_F635_419A_9E10_159485D0F710_H_
#pragma once

#include "cxx/ResourceHolder.hpp"
#if defined(_WIN32)
#include "util/sync/MutexHandle.hpp"
#endif

#include <chrono>
#if !defined(_WIN32)
#include <memory>
#include <mutex>
#endif

#include <Windows.h>

/*!
 * @brief ミューテックスを扱うクラス
 *
 * @date 2007/07/05 ryoji 新規作成
 */
class CMutex
{
private:
#if defined(_WIN32)
	using MutexHandle = cxx::MutexHandle;
	using LockHolder = cxx::ResourceHolder<&::ReleaseMutex>;
#endif

	using Me = CMutex;

public:
	explicit CMutex(
		sakura::wstring_view name,
		LPSECURITY_ATTRIBUTES psa = nullptr,
		bool bInitialOwner = false
	);

	CMutex(
		BOOL bInitialOwner,
		LPCWSTR pszName,
		LPSECURITY_ATTRIBUTES psa = nullptr
	);

	CMutex(const Me&) = delete;
	Me& operator = (const Me&) = delete;

	void lock();
	void unlock() noexcept;

	template <class Rep, class Period>
	bool try_lock_for(
		const std::chrono::duration<Rep, Period>& timeout
	)
	{
		const auto milliseconds = std::chrono::duration_cast<std::chrono::milliseconds>(timeout);
		return Lock(static_cast<DWORD>(milliseconds.count()));
	}

	bool Lock(
		DWORD dwTimeout = INFINITE
	);

	void Unlock() noexcept;

#if defined(_WIN32)
	operator HANDLE() const { return m_hObj; }
#endif

private:
	sakura::wstring_view m_Name;
	LPSECURITY_ATTRIBUTES m_pSa;
	bool m_bInitialOwner;

#if defined(_WIN32)
	MutexHandle m_hObj{};
	LockHolder	m_Lock{};
#else
	// Mac 版：プロセスは 1 つだけなので、名前付きミューテックスはプロセス内の再帰ミューテックスで代用する
	// （同じ名前の CMutex は同じミューテックスを共有する。移植計画のステップ 21）
	std::shared_ptr<std::recursive_timed_mutex> m_pMutex{};
	bool m_bLocked = false;
#endif
};

/**	スコープから抜けると同時にロックを解除する．

	@date 2007.07.07 genta 新規作成

	@code
	CMutex aMutex;
	
    void function()
    {
        //  other processing
        {
            LockGuard<CMutex> aGuard(aMutex);
            //  aMutex is locked
            //  do something protected by "aMutex"

        } // aMutex is automatically released
        //  other processing
    }
	@endcode
*/
//TODO: いつかコメント外す
//[[deprecated( "Use std::lock_guard or std::unique_lock instead" )]] ]
template<class EXCLUSIVE_OBJECT>
class LockGuard {
	using Me = LockGuard< EXCLUSIVE_OBJECT>;

	EXCLUSIVE_OBJECT& o_;

public:
	explicit LockGuard(EXCLUSIVE_OBJECT& ex) : o_( ex ){
		o_.Lock();
	}
	template<class PARAM>
	LockGuard(EXCLUSIVE_OBJECT& ex, PARAM p) : o_( ex ){
		o_.Lock(p);
	}
	LockGuard(const Me&) = delete;
	Me& operator = (const Me&) = delete;
	LockGuard(Me&&) noexcept = delete;
	Me& operator = (Me&&) noexcept = delete;
	~LockGuard() {
		o_.Unlock();
	}
};

#endif /* SAKURA_CMUTEX_51EDDE78_F635_419A_9E10_159485D0F710_H_ */
