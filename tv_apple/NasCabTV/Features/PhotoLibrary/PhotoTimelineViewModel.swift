import Foundation
import SwiftUI

// MARK: - Grouped Section for UI

struct TVPhotoTimelineGroupedSection: Identifiable {
    let id: String
    let dateLabel: String
    let photos: [TVPhotoTimelinePhotoItem]
}

// MARK: - Timeline ViewModel

@MainActor
final class TVPhotoTimelineViewModel: ObservableObject {
    @Published private(set) var groupedSections: [TVPhotoTimelineGroupedSection] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isInitialLoaded = false
    @Published private(set) var errorMessage: String?

    @Published var searchText: String = ""
    @Published var sortOrder: String = "desc"
    @Published var fileType: String = "all"
    @Published var selectedPaths: Set<String> = []
    @Published var availablePaths: [TVPhotoTimelinePathItem] = []
    @Published var selectedMonth: String? = nil  // "YYYY-MM"
    @Published var availableMonths: [String] = []

    private var dateList: [TVPhotoTimelineDateItem] = []
    private var photoCache: [String: [TVPhotoTimelinePhotoItem]] = [:]
    private let initialYear: Int?
    private let loadTheDay: Bool
    private let albumId: Int?
    private let collectionId: Int?
    private let smartAlbumId: Int?
    private let listType: String?

    init(
        initialYear: Int? = nil,
        loadTheDay: Bool = false,
        albumId: Int? = nil,
        collectionId: Int? = nil,
        smartAlbumId: Int? = nil,
        listType: String? = nil
    ) {
        self.initialYear = initialYear
        self.loadTheDay = loadTheDay
        self.albumId = albumId
        self.collectionId = collectionId
        self.smartAlbumId = smartAlbumId
        self.listType = listType?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
            ? nil
            : listType?.trimmingCharacters(in: .whitespacesAndNewlines)
        if loadTheDay {
            sortOrder = "desc"
        }
    }

    var sourceFilterCount: Int { selectedPaths.count }

    var currentSortLabel: String {
        if isFavoriteList {
            return sortOrder == "desc" ? L10n.videoSortFavoriteTimeDesc : L10n.videoSortFavoriteTimeAsc
        }
        return sortOrder == "desc" ? L10n.photoTimelineSortDesc : L10n.photoTimelineSortAsc
    }

    var isFavoriteList: Bool { listType == "favorite" }

    var fileTypeLabel: String {
        switch fileType {
        case "photo": return L10n.timelinePhotos
        case "video": return L10n.timelineVideos
        case "livephoto": return L10n.timelineLivePhotos
        default: return L10n.allLabel
        }
    }

    var monthFilterLabel: String {
        if let m = selectedMonth {
            return monthDisplayLabel(for: m)
        }
        return L10n.photoTimelineFilterMonth
    }

    func monthDisplayLabel(for monthKey: String) -> String {
        let parts = monthKey.split(separator: "-")
        guard parts.count == 2,
              let y = Int(parts[0]),
              let mo = Int(parts[1]) else {
            return monthKey
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.currentLanguageCode.hasPrefix("zh") ? "zh_CN" : "en_US")
        formatter.dateFormat = "MMMM"
        var comps = DateComponents()
        comps.month = mo
        comps.year = y
        if let date = Calendar.current.date(from: comps) {
            let monthName = formatter.string(from: date)
            return L10n.currentLanguageCode.hasPrefix("zh") ? "\(y)年\(monthName)" : "\(monthName) \(y)"
        }
        return "\(y)-\(String(format: "%02d", mo))"
    }

    func loadInitialIfNeeded() async {
        guard !isInitialLoaded else { return }
        await reload()
    }

    func reload() async {
        print("[PhotoTimeline] reload() started, initialYear=\(String(describing: initialYear)), selectedMonth=\(String(describing: selectedMonth))")
        isLoading = true
        errorMessage = nil

        let sort = sortOrder
        let fileTypeParam = fileType == "all" ? nil : fileType
        let searchParam = searchText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : searchText.trimmingCharacters(in: .whitespaces)
        let sourceListParam = selectedPaths.isEmpty ? nil : Array(selectedPaths)
        var yearParam: Int? = initialYear
        if selectedMonth != nil, let m = selectedMonth {
            let parts = m.split(separator: "-")
            if let y = Int(parts.first ?? "0") {
                yearParam = y
            }
        }

        let dateResponse = await TVPhotoTimelineService.getTimelineDateList(
            sort: sort,
            fileType: fileTypeParam,
            search: searchParam,
            sourceList: sourceListParam,
            year: yearParam,
            loadTheDay: loadTheDay,
            albumId: albumId,
            collectionId: collectionId,
            smartAlbumId: smartAlbumId,
            listType: listType
        )

        guard dateResponse.success, let dateData = dateResponse.data else {
            print("[PhotoTimeline] dates API failed: success=\(dateResponse.success), message=\(dateResponse.message ?? "nil")")
            errorMessage = dateResponse.message ?? L10n.networkFailure
            isLoading = false
            isInitialLoaded = true
            groupedSections = []
            return
        }

        dateList = dateData.items
        print("[PhotoTimeline] dates loaded: count=\(dateList.count), firstFew=\(dateList.prefix(3).map { $0.originalDate })")
        if !dateData.validPaths.isEmpty {
            availablePaths = dateData.validPaths
        }
        availableMonths = Array(Set(dateList.map { $0.monthYearKey })).sorted(by: >)

        if dateList.isEmpty {
            print("[PhotoTimeline] dateList empty, returning")
            groupedSections = []
            isLoading = false
            isInitialLoaded = true
            return
        }

        let datesToFetch = selectedMonth != nil
            ? dateList.filter { $0.monthYearKey == selectedMonth }
            : dateList

        var allSections: [TVPhotoTimelineGroupedSection] = []
        print("[PhotoTimeline] datesToFetch count=\(datesToFetch.count), monthsToLoad branch: selectedMonth=\(String(describing: selectedMonth))")

        if let monthKey = selectedMonth {
            let datesInMonth = datesToFetch
            guard let firstDate = datesInMonth.first?.originalDate,
                  let lastDate = datesInMonth.last?.originalDate else {
                groupedSections = []
                isLoading = false
                isInitialLoaded = true
                return
            }
            let startTime = parseDateToTimestamp(firstDate, endOfDay: false)
            let endTime = parseDateToTimestamp(lastDate, endOfDay: true)

            let photoResponse = await TVPhotoTimelineService.getTimelinePhotoList(
                sort: sort,
                fileType: fileTypeParam,
                startTime: startTime,
                endTime: endTime,
                search: searchParam,
                sourceList: sourceListParam,
                year: yearParam,
                loadTheDay: loadTheDay,
                albumId: albumId,
                collectionId: collectionId,
                smartAlbumId: smartAlbumId,
                listType: listType
            )

            if photoResponse.success, let photoData = photoResponse.data, !photoData.photoList.isEmpty {
                print("[PhotoTimeline] monthFilter: got \(photoData.photoList.count) photos")
                let groupedByDate = Dictionary(grouping: photoData.photoList) { $0.originalDate }
                for dateItem in datesInMonth.sorted(by: { $0.originalDate > $1.originalDate }) {
                    let photos = groupedByDate[dateItem.originalDate] ?? []
                    if !photos.isEmpty {
                        let section = TVPhotoTimelineGroupedSection(
                            id: dateItem.originalDate,
                            dateLabel: formatDateLabel(dateItem.originalDate),
                            photos: sortOrder == "desc" ? photos : photos.reversed()
                        )
                        allSections.append(section)
                    }
                }
                allSections.sort { $0.id > $1.id }
                if sortOrder == "asc" {
                    allSections.reverse()
                }
            } else {
                print("[PhotoTimeline] monthFilter: photoResponse failed or empty, success=\(photoResponse.success), photoCount=\(photoResponse.data?.photoList.count ?? 0)")
            }
        } else {
            let monthGroups = Dictionary(grouping: datesToFetch) { $0.monthYearKey }
            let sortedMonths = monthGroups.keys.sorted(by: >)
            let monthsToLoad = Array(sortedMonths.prefix(6))
            print("[PhotoTimeline] timeline branch: monthGroups=\(sortedMonths), loading months=\(monthsToLoad)")

            for monthKey in monthsToLoad {
                guard let datesInMonth = monthGroups[monthKey]?.sorted(by: { $0.originalDate > $1.originalDate }),
                      let firstDate = datesInMonth.last?.originalDate,
                      let lastDate = datesInMonth.first?.originalDate else { continue }

                let startTime = parseDateToTimestamp(firstDate, endOfDay: false)
                let endTime = parseDateToTimestamp(lastDate, endOfDay: true)

                let photoResponse = await TVPhotoTimelineService.getTimelinePhotoList(
                    sort: sort,
                    fileType: fileTypeParam,
                    startTime: startTime,
                    endTime: endTime,
                    search: searchParam,
                    sourceList: sourceListParam,
                    year: yearParam,
                    loadTheDay: loadTheDay,
                    albumId: albumId,
                    collectionId: collectionId,
                    smartAlbumId: smartAlbumId,
                    listType: listType
                )

                guard photoResponse.success, let photoData = photoResponse.data else {
                    print("[PhotoTimeline] month \(monthKey): photo API failed")
                    continue
                }
                print("[PhotoTimeline] month \(monthKey): got \(photoData.photoList.count) photos")

                let groupedByDate = Dictionary(grouping: photoData.photoList) { $0.originalDate }
                for dateItem in datesInMonth {
                    let photos = groupedByDate[dateItem.originalDate] ?? []
                    if !photos.isEmpty {
                        let section = TVPhotoTimelineGroupedSection(
                            id: dateItem.originalDate,
                            dateLabel: formatDateLabel(dateItem.originalDate),
                            photos: sortOrder == "desc" ? photos : photos.reversed()
                        )
                        allSections.append(section)
                    }
                }
            }
            allSections.sort { $0.id > $1.id }
            if sortOrder == "asc" {
                allSections.reverse()
            }
        }

        groupedSections = allSections
        print("[PhotoTimeline] reload done: groupedSections=\(allSections.count)")
        isLoading = false
        isInitialLoaded = true
    }

    private func parseDateToTimestamp(_ dateStr: String, endOfDay: Bool) -> Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        guard let date = formatter.date(from: dateStr) else {
            return 0
        }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        if endOfDay {
            comps.hour = 23
            comps.minute = 59
            comps.second = 59
        } else {
            comps.hour = 0
            comps.minute = 0
            comps.second = 0
        }
        guard let finalDate = Calendar.current.date(from: comps) else {
            return 0
        }
        // 服务端期望毫秒时间戳（与 Flutter 一致）
        return Int(finalDate.timeIntervalSince1970 * 1000)
    }

    private func formatDateLabel(_ dateStr: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        guard let date = formatter.date(from: dateStr) else {
            return dateStr
        }
        let displayFormatter = DateFormatter()
        displayFormatter.locale = Locale(identifier: L10n.currentLanguageCode.hasPrefix("zh") ? "zh_CN" : "en_US")
        displayFormatter.dateFormat = L10n.currentLanguageCode.hasPrefix("zh") ? "yyyy年M月d日" : "MMM d, yyyy"
        return displayFormatter.string(from: date)
    }

    func applySearch(text: String) {
        searchText = text.trimmingCharacters(in: .whitespaces)
        Task { await reload() }
    }

    func clearSearchAndReload() {
        guard !searchText.isEmpty else { return }
        searchText = ""
        Task { await reload() }
    }

    func applySortOrder(_ order: String) {
        guard sortOrder != order else { return }
        sortOrder = order
        Task { await reload() }
    }

    func toggleSortOrder() {
        applySortOrder(sortOrder == "desc" ? "asc" : "desc")
    }

    func applyFileType(_ type: String) {
        guard fileType != type else { return }
        fileType = type
        Task { await reload() }
    }

    func toggleSource(path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        if selectedPaths.contains(trimmed) {
            selectedPaths.remove(trimmed)
        } else {
            selectedPaths.insert(trimmed)
        }
        Task { await reload() }
    }

    func resetSourceFilter() {
        guard !selectedPaths.isEmpty else { return }
        selectedPaths.removeAll()
        Task { await reload() }
    }

    func applyMonthFilter(_ monthKey: String) {
        selectedMonth = monthKey
        Task { await reload() }
    }

    func clearMonthFilter() {
        guard selectedMonth != nil else { return }
        selectedMonth = nil
        Task { await reload() }
    }
}

// MARK: - Year ViewModel

@MainActor
final class TVPhotoYearViewModel: ObservableObject {
    @Published private(set) var items: [TVPhotoTimelineYearItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isInitialLoaded = false
    @Published private(set) var errorMessage: String?

    func loadInitialIfNeeded() async {
        guard !isInitialLoaded else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil

        let response = await TVPhotoTimelineService.getTimelineYearList()

        guard response.success, let data = response.data else {
            errorMessage = response.message ?? L10n.networkFailure
            isLoading = false
            isInitialLoaded = true
            items = []
            return
        }

        items = data.items.sorted { $0.year > $1.year }
        isLoading = false
        isInitialLoaded = true
    }
}

// MARK: - Today ViewModel

@MainActor
final class TVPhotoTodayViewModel: ObservableObject {
    @Published private(set) var photos: [TVPhotoTimelinePhotoItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isInitialLoaded = false
    @Published private(set) var errorMessage: String?

    @Published var searchText: String = ""
    @Published var sortOrder: String = "desc"

    var currentSortLabel: String {
        sortOrder == "desc" ? L10n.photoTimelineSortDesc : L10n.photoTimelineSortAsc
    }

    func loadInitialIfNeeded() async {
        guard !isInitialLoaded else { return }
        await reload()
    }

    func reload() async {
        isLoading = true
        errorMessage = nil

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        let todayStr = formatter.string(from: Date())

        let startTime = parseDateToTimestamp(todayStr, endOfDay: false)
        let endTime = parseDateToTimestamp(todayStr, endOfDay: true)

        let searchParam = searchText.trimmingCharacters(in: .whitespaces).isEmpty ? nil : searchText.trimmingCharacters(in: .whitespaces)

        let response = await TVPhotoTimelineService.getTimelinePhotoList(
            sort: sortOrder,
            fileType: nil,
            startTime: startTime,
            endTime: endTime,
            search: searchParam,
            sourceList: nil,
            year: nil,
            loadTheDay: true
        )

        guard response.success, let data = response.data else {
            errorMessage = response.message ?? L10n.networkFailure
            isLoading = false
            isInitialLoaded = true
            photos = []
            return
        }

        photos = data.photoList
        isLoading = false
        isInitialLoaded = true
    }

    private func parseDateToTimestamp(_ dateStr: String, endOfDay: Bool) -> Int {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        guard let date = formatter.date(from: dateStr) else { return 0 }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        if endOfDay {
            comps.hour = 23
            comps.minute = 59
            comps.second = 59
        } else {
            comps.hour = 0
            comps.minute = 0
            comps.second = 0
        }
        guard let finalDate = Calendar.current.date(from: comps) else { return 0 }
        // 服务端期望毫秒时间戳（与 Flutter 一致）
        return Int(finalDate.timeIntervalSince1970 * 1000)
    }

    func applySearch(text: String) {
        searchText = text.trimmingCharacters(in: .whitespaces)
        Task { await reload() }
    }

    func clearSearchAndReload() {
        guard !searchText.isEmpty else { return }
        searchText = ""
        Task { await reload() }
    }

    func toggleSortOrder() {
        sortOrder = sortOrder == "desc" ? "asc" : "desc"
        Task { await reload() }
    }
}
