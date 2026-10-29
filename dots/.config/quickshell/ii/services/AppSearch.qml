pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import Quickshell
import QtQuick

/**
 * - Eases fuzzy searching for applications by name
 * - Guesses icon name for window class name
 */
Singleton {
    id: root
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property real scoreThreshold: 0.2
    // Hard cap on the number of matches returned. Every match becomes a
    // LauncherSearchResult (plus one object per desktop action) and the UI only
    // ever shows the first handful, so an uncapped short query is pure churn.
    // Roughly 2x SearchWidget's typingResultLimit (15), so the list still has
    // rows to grow into while the rest of the results stream in.
    property int maxResults: 30
    property var substitutions: ({
        "code-url-handler": "visual-studio-code",
        "Code": "visual-studio-code",
        "gnome-tweaks": "org.gnome.tweaks",
        "pavucontrol-qt": "pavucontrol",
        "wps": "wps-office2019-kprometheus",
        "wpsoffice": "wps-office2019-kprometheus",
        "footclient": "foot",
    })
    property var regexSubstitutions: [
        {
            "regex": /^steam_app_(\d+)$/,
            "replace": "steam_icon_$1"
        },
        {
            "regex": /Minecraft.*/,
            "replace": "minecraft"
        },
        {
            "regex": /.*polkit.*/,
            "replace": "system-lock-screen"
        },
        {
            "regex": /gcr.prompter/,
            "replace": "system-lock-screen"
        }
    ]

    // Cache
    property var _iconCache: ({})
    property var list: []
    property var preppedNames: []
    property var preppedIcons: []

    // Debounce Application Re-indexing
    Timer {
        id: reindexTimer
        interval: 300
        repeat: false
        onTriggered: root.rebuildIndex()
    }

    Connections {
        target: DesktopEntries.applications

        // Coalesce the re-index, but do not starve it: restarting the timer on
        // every change would keep the index empty until the desktop entry scan
        // goes quiet, which takes seconds while the thread pool trickles entries
        // in. Starting it only when it is idle already bounds the staleness to
        // one interval.
        function onValuesChanged(){
            if (!reindexTimer.running)
                reindexTimer.start()
        }
    }

    Component.onCompleted: {
        root.rebuildIndex()
    }

    function fuzzyQuery(search: string): var { // Idk why list<DesktopEntry> doesn't work
        // An empty search means "no filter" and not "no results": typing the app
        // prefix on its own (">") is how the launcher lists every app.
        if (search.length === 0) return root.list;

        if (root.sloppySearch) {
            // Scores against the name, like before: the Levenshtein ratio is
            // normalised by the longer string, so feeding it the whole
            // name+id+comment blob collapses every score below the threshold.
            const q = search.toLowerCase();
            const scored = [];
            for (const obj of root.preppedNames) {
                // Substring hit: skip the expensive Levenshtein call.
                const score = obj.lowerName.includes(q) ? 1.0 : Levendist.computeScore(obj.lowerName, q);
                if (score > root.scoreThreshold) scored.push({ entry: obj.entry, score });
            }
            scored.sort((a, b) => b.score - a.score);
            return scored.slice(0, root.maxResults).map(item => item.entry);
        }

        // name + id only. fuzzysort matches subsequences, so including the
        // comment/keywords blob makes any 4-letter query hit dozens of entries
        // ("fire" came back with SongRec first, through the f in "for", the i in
        // "written", ...). The id still carries the English name of localized
        // entries ("org.gnome.Snapshot" for 相机), which is the part worth
        // matching on.
        return Fuzzy.go(search, root.preppedNames, {
            limit: root.maxResults,
            keys: ["name", "id"]
        }).map(r => {
            return r.obj.entry
        });
    }

    function iconExists(iconName) {
        if (!iconName || iconName.length == 0) return false;
        return (Quickshell.iconPath(iconName, true).length > 0) 
            && !iconName.includes("image-missing");
    }

    function getReverseDomainNameAppName(str) {
        return str.split('.').slice(-1)[0]
    }

    function getKebabNormalizedAppName(str) {
        return str.toLowerCase().replace(/\s+/g, "-");
    }

    function getUndescoreToKebabAppName(str) {
        return str.toLowerCase().replace(/_/g, "-");
    }

    function guessIcon(str) {
        if (!str || str.length == 0) return "image-missing";

        // First check the icon cache. Use hasOwnProperty so keys like
        // "constructor" / "toString" don't resolve through Object.prototype.
        if (Object.prototype.hasOwnProperty.call(_iconCache, str)) {
            return _iconCache[str];
        }

        let res = (function(){
            // Quickshell's desktop entry lookup
            const entry = DesktopEntries.byId(str);
            if (entry) return entry.icon;
    
            // Normal substitutions
            if (substitutions[str]) return substitutions[str];
            if (substitutions[str.toLowerCase()]) return substitutions[str.toLowerCase()];
    
            // Regex substitutions
            for (let i = 0; i < regexSubstitutions.length; i++) {
                const substitution = regexSubstitutions[i];
                const replacedName = str.replace(
                    substitution.regex,
                    substitution.replace,
                );
                if (replacedName != str) return replacedName;
            }
    
            // Icon exists -> return as is
            if (iconExists(str)) return str;
    
    
            // Simple guesses
            const lowercased = str.toLowerCase();
            if (iconExists(lowercased)) return lowercased;
    
            const reverseDomainNameAppName = getReverseDomainNameAppName(str);
            if (iconExists(reverseDomainNameAppName)) return reverseDomainNameAppName;
    
            const lowercasedDomainNameAppName = reverseDomainNameAppName.toLowerCase();
            if (iconExists(lowercasedDomainNameAppName)) return lowercasedDomainNameAppName;
    
            const kebabNormalizedGuess = getKebabNormalizedAppName(str);
            if (iconExists(kebabNormalizedGuess)) return kebabNormalizedGuess;
    
            const undescoreToKebabGuess = getUndescoreToKebabAppName(str);
            if (iconExists(undescoreToKebabGuess)) return undescoreToKebabGuess;
    
            // Search in desktop entries
            const iconSearchResults = Fuzzy.go(str, preppedIcons, {
                all: true,
                key: "name"
            }).map(r => {
                return r.obj.entry
            });
            if (iconSearchResults.length > 0) {
                const guess = iconSearchResults[0].icon
                if (iconExists(guess)) return guess;
            }
    
            const nameSearchResults = root.fuzzyQuery(str);
            if (nameSearchResults.length > 0) {
                const guess = nameSearchResults[0].icon
                if (iconExists(guess)) return guess;
            }
    
            // Quickshell's desktop entry lookup
            const heuristicEntry = DesktopEntries.heuristicLookup(str);
            if (heuristicEntry) return heuristicEntry.icon;
    
            // Give up
            return "application-x-executable";
        })();

        // Save it to cache and return
        _iconCache[str] = res;
        return res;
    }

    function rebuildIndex() {
        const rawApps = DesktopEntries.applications.values;
        if (!rawApps) return;

        // Installed apps changed: icon guesses computed from the old entries may be stale
        root._iconCache = ({});

        // Optimize Deduplication Complexity
        // Keep the first entry per id like the old `findIndex` filter did,
        // including entries without an id: they all share the empty key, so only
        // the first of them survives, which is exactly what the old filter did
        // (it compared ids too). Dropping them outright hides apps, which is
        // what the Set version introduced.
        const seenIds = new Set();
        const dedupedList = [];
        for (let i = 0; i < rawApps.length; i++) {
            const app = rawApps[i];
            if (!app) continue;
            const key = app.id ?? "";
            if (seenIds.has(key)) continue;
            seenIds.add(key);
            dedupedList.push(app);
        }
        root.list = dedupedList;

        // Pre-compute the per-entry search strings once per index rebuild instead
        // of re-deriving them on every keystroke.
        root.preppedNames = dedupedList.map(a => ({
            name: Fuzzy.prepare(`${a.name ?? ""} `),
            id: Fuzzy.prepare(`${a.id ?? ""} `),
            lowerName: `${a.name ?? ""}`.toLowerCase(),
            entry: a
        }));

        root.preppedIcons = dedupedList.map(a => ({
            name: Fuzzy.prepare(`${a.icon} `),
            entry: a
        }));
    }

}
