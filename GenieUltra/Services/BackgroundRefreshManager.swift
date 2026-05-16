// BackgroundRefreshManager.swift — removed.
//
// Alert delivery is now handled entirely by the Cloudflare Worker, which polls
// themeparks.wiki every minute and pushes via ntfy.sh / Telegram. iOS background
// tasks (BGAppRefreshTask) are no longer scheduled or registered.
//
// Foreground alert checks still run via DashboardView.onChange(of: store.attractions).
// History persistence still runs via ParkDataStore.processLiveData() → PersistedWaitHistory.
