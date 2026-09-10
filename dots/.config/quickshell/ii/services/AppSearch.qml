pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import Quickshell
import QtQuick 2.15

/**
 * - Eases fuzzy searching for applications by name
 * - Guesses icon name for window class name
 */
Singleton {
    id: root
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property real scoreThreshold: 0.2
    // 搜索结果上限:防止短查询匹配到几百条时 LauncherSearch 为每条 createObject 导致卡顿
    property int maxResults: 30
    property var _iconCache: ({})
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

    // Deduped list to fix double icons
    /*readonly property list<DesktopEntry> list: Array.from(DesktopEntries.applications.values)
        .filter((app, index, self) => 
            index === self.findIndex((t) => (
                t.id === app.id
            ))
    )
    
    // 预计算搜索索引(仅应用列表变化时计算一次):
    // - name/id/extra 分字段 prepare 供 fuzzysort keys 匹配(独立评分,不被长串稀释)
    // - merged 合并小写串供 sloppySearch 使用(子串短路 + 单次 Levenshtein)
    readonly property var preppedNames: list.map(a => ({
        name: Fuzzy.prepare(`${a.name} `),
        id: Fuzzy.prepare(`${a.id} `),
        extra: Fuzzy.prepare(`${a.genericName ?? ""} ${a.comment ?? ""} ${(a.keywords ?? []).join(" ")} `),
        merged: `${a.name} ${a.id} ${a.genericName ?? ""} ${a.comment ?? ""} ${(a.keywords ?? []).join(" ")}`.toLowerCase(),
        entry: a
    }))

    readonly property var preppedIcons: list.map(a => ({
        name: Fuzzy.prepare(`${a.icon} `),
        entry: a
    }))*/

    property var list: []
    property var preppedNames: []
    property var preppedIcons: []

    Timer {
        id: reindexTimer
        interval: 300
        repeat: false
        onTriggered: root.rebuildIndex()
    }

    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() {
            // 只要系统桌面条目还在频繁变动，就一直重置定时器，直到平静后才开始计算
            reindexTimer.restart()
        }
    }

    Component.onCompleted: {
        root.rebuildIndex()
    }

    // ==========================================
    // 💡 2. O(N) 高效重建索引函数
    // ==========================================
    function rebuildIndex() {
        const rawApps = DesktopEntries.applications.values;
        if (!rawApps) return;

        // 2.1 O(N) 高性能去重（使用 Set 替代原有的 filter + findIndex）
        const seenIds = new Set();
        const dedupedList = [];
        for (let i = 0; i < rawApps.length; i++) {
            const app = rawApps[i];
            if (app && app.id && !seenIds.has(app.id)) {
                seenIds.add(app.id);
                dedupedList.push(app);
            }
        }
        root.list = dedupedList;

        // 2.2 预计算搜索索引
        root.preppedNames = dedupedList.map(a => ({
            name: Fuzzy.prepare(`${a.name} `),
            id: Fuzzy.prepare(`${a.id} `),
            extra: Fuzzy.prepare(`${a.genericName ?? ""} ${a.comment ?? ""} ${(a.keywords ?? []).join(" ")} `),
            merged: `${a.name} ${a.id} ${a.genericName ?? ""} ${a.comment ?? ""} ${(a.keywords ?? []).join(" ")}`.toLowerCase(),
            entry: a
        }));

        root.preppedIcons = dedupedList.map(a => ({
            name: Fuzzy.prepare(`${a.icon} `),
            entry: a
        }));
    }

    /**
     * 模糊搜索应用。参数 search: 用户输入的查询串;返回匹配的 DesktopEntry 数组。
     * sloppySearch 开启时:合并串子串短路命中直接满分(零 Levenshtein),
     *   未命中再用 Levenshtein 下界剪枝(|len1-len2| 过大必然低于阈值,直接跳过)减少无效计算。
     * fuzzysort 路径:name/id/extra 分字段 keys 匹配取最优评分,limit 限制返回条数避免 UI 创建过多结果对象。
     */
    function fuzzyQuery(search: string): var { // Idk why list<DesktopEntry> doesn't work
        if (root.sloppySearch) {
            const q = search.toLowerCase();
            const results = [];
            for (const obj of root.preppedNames) {
                let score;
                if (obj.merged.includes(q)) {
                    score = 1.0; // 子串命中:快速路径,避免昂贵的 Levenshtein
                } else {
                    // Levenshtein 距离下界 = |len1-len2|;若下界已使分数 <= 阈值则必然不匹配
                    const maxLen = Math.max(obj.merged.length, q.length);
                    if (maxLen === 0) {
                        score = 1.0;
                    } else if (Math.abs(obj.merged.length - q.length) >= (1 - root.scoreThreshold) * maxLen) {
                        continue;
                    } else {
                        score = Levendist.computeScore(obj.merged, q);
                    }
                }
                if (score > root.scoreThreshold) results.push({ entry: obj.entry, score });
            }
            results.sort((a, b) => b.score - a.score);
            return results.slice(0, root.maxResults).map(item => item.entry);
        }

        return Fuzzy.go(search, root.preppedNames, {
            all: true,
            limit: root.maxResults,
            keys: ["name", "id", "extra"]
        }).map(r => {
            return r.obj.entry
        });
    }

    function iconExists(iconName) {
        if (!iconName || iconName.length === 0) return false;
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
        if (!str || str.length === 0) return "image-missing";

        // 💡 1. 优先查缓存：如果之前推导过这个 Class 的图标，直接 O(1) 毫秒级返回
        if (_iconCache[str] !== undefined) {
            return _iconCache[str];
        }

        // 内部计算真实图标的辅助闭包
        let res = (function() {
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
                if (replacedName !== str) return replacedName;
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

            // 💡 2. 优化：只用轻量级的 heuristicLookup，移除了耗时的 root.fuzzyQuery(str) 全量模糊匹配
            const heuristicEntry = DesktopEntries.heuristicLookup(str);
            if (heuristicEntry) return heuristicEntry.icon;

            // Search in desktop entries (仅当极少数情况下尝试轻量 icon 搜索)
            const iconSearchResults = Fuzzy.go(str, preppedIcons, {
                all: false, // 💡 改为 false，匹配到即停止，不强行遍历全量数组
                limit: 1,
                key: "name"
            }).map(r => r.obj.entry);

            if (iconSearchResults.length > 0) {
                const guess = iconSearchResults[0].icon;
                if (iconExists(guess)) return guess;
            }

            // Give up
            return "application-x-executable";
        })();

        // 💡 3. 将计算出的结果写入缓存
        _iconCache[str] = res;
        return res;
    }

}
