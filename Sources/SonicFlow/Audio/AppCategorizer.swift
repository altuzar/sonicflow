import Foundation

enum AppCategorizer {
    /// Map a bundle ID to a category. Unknown apps default to .other —
    /// safest bet, since misclassifying a random tool as "communication"
    /// would trip ducking on every notification sound.
    static func category(for bundleID: String?) -> AppCategory {
        guard let id = bundleID?.lowercased() else { return .other }

        if communication.contains(where: { id.contains($0) }) { return .communication }
        if browser.contains(where: { id.contains($0) })       { return .browser }
        if media.contains(where: { id.contains($0) })         { return .media }
        if game.contains(where: { id.contains($0) })          { return .game }

        return .other
    }

    /// Substring-matched. We use `contains` because helper processes get suffixes
    /// (e.g. "us.zoom.xos.callservice", "com.microsoft.teams2.helper").
    private static let communication = [
        "us.zoom.xos",
        "us.zoom",
        "com.microsoft.teams",
        "com.tinyspeck.slackmacgap",
        "com.cisco.webexmeetingsapp",
        "com.skype",
        "com.facetime",
        "com.apple.facetime",
        "com.apple.facetimeagent",
        "ru.keepcoder.telegram",
        "com.discord",
        "com.hnc.discord",
        "com.google.meet",
        "com.whatsapp",
        "com.signal.signal-desktop"
    ]

    private static let browser = [
        "com.google.chrome",
        "com.apple.safari",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",
        "com.brave.browser",
        "com.brave.browser.nightly",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.beta",
        "com.microsoft.edgemac.dev",
        "com.operasoftware.opera",
        "com.operasoftware.operagx",
        "company.thebrowser.browser",    // Arc
        "company.thebrowser.dia",        // Dia
        "com.vivaldi.vivaldi",
        "org.chromium.chromium",
        "com.duckduckgo.macos.browser",
        "net.kovidgoyal.kitty",          // (terminal but supports audio bell)
        "com.mighty.app",                // Mighty
        "ru.yandex.desktop.yandex-browser",
        "com.tencent.qqbrowser"
    ]

    private static let media = [
        "com.spotify.client",
        "com.apple.music",
        "com.apple.tv",
        "com.apple.itunes",
        "com.apple.podcasts",
        "com.colliderli.iina",
        "org.videolan.vlc",
        "com.netflix.netflix",
        "com.youtube",
        "com.soundcloud",
        "com.pandora",
        "com.tidal",
        "com.tidal.desktop",
        "com.amazon.music",
        "com.amazon.aiv.AIVApp",         // Prime Video
        "com.audirvana.Audirvana",
        "com.sonos.macController2",
        "com.plexapp.plex",
        "com.plexamp.app",
        "tv.plex.plexamp",
        "com.swinsian.Swinsian",
        "fm.last.Last.fm",
        "io.cog.cog",                    // Cog
        "com.deezer.deezer-desktop",
        "com.qobuz.qobuz-mac",
        "com.movist.movist",
        "tw.uxteam.movist-pro",
        "com.disneyplus.DisneyPlus",
        "com.hulu.HuluMacApp",
        "com.atomic.tomatobit"           // generic fallback
    ]

    private static let game = [
        "com.valvesoftware.steam",
        "com.epicgames",
        "com.blizzard"
    ]
}
