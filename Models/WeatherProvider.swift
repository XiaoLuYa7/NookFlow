import CoreLocation
import Foundation

struct WeatherSnapshot {
    var temperature: Double?
    var apparentTemperature: Double?
    var humidity: Int?
    var windSpeed: Double?
    var condition: String
    var locationName: String
    var symbolName: String
    var detail: String
    var dailyForecasts: [WeatherDailySummary] = []
    var isLive: Bool

    static let placeholder = WeatherSnapshot(
        temperature: nil,
        apparentTemperature: nil,
        humidity: nil,
        condition: "定位中",
        locationName: "当前位置",
        symbolName: "location.fill",
        detail: "正在获取天气",
        isLive: false
    )

    var temperatureText: String {
        guard let temperature else { return "--°" }
        return "\(Int(temperature.rounded()))°"
    }

    var isLoading: Bool {
        !isLive && (condition == "定位中" || condition == "加载中")
    }
}

struct WeatherDailySummary: Identifiable {
    let id: String
    var title: String
    var symbolName: String
    var temperatureRangeText: String
}

final class WeatherProvider: NSObject, ObservableObject, CLLocationManagerDelegate {

    @Published private(set) var snapshot: WeatherSnapshot = .placeholder

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var hasStarted = false
    private var lastSuccessfulRefresh: Date?
    private var weatherTask: Task<Void, Never>?
    private var refreshTimer: Timer?
    private var scheduledRefreshInterval: TimeInterval?
    private var locationTimeoutTimer: Timer?
    private var isLocationUpdateActive = false
    private var hasUsableLocationForCurrentRequest = false
    private var weatherRequestGeneration: UInt64 = 0
    private static let authorizationRequestLock = NSLock()
    private static var authorizationRequestInFlight = false
    private static let defaultRefreshInterval: TimeInterval = 15 * 60
    private static let locationTimeout: TimeInterval = 30
    private static let systemLocationMaxAge: TimeInterval = 24 * 60 * 60
    private static let persistedLocationMaxAge: TimeInterval = 30 * 24 * 60 * 60

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    deinit {
        refreshTimer?.invalidate()
        locationTimeoutTimer?.invalidate()
        weatherTask?.cancel()
        geocoder.cancelGeocode()
        manager.stopUpdatingLocation()
        manager.delegate = nil
    }

    func start(autoRefreshInterval: TimeInterval? = defaultRefreshInterval, reuseRecentSnapshot: Bool = false) {
        let snapshotIsRecent = reuseRecentSnapshot && snapshot.isLive
            && (lastSuccessfulRefresh?.timeIntervalSinceNow ?? -.infinity) > -60
        let shouldRequestLocation = (!hasStarted && !snapshotIsRecent)
            || (!snapshot.isLive && !isLocationUpdateActive)
        hasStarted = true
        if shouldRequestLocation {
            requestLocationIfPossible()
        }
        configureAutoRefresh(interval: autoRefreshInterval)
    }

    func refresh() {
        hasStarted = true
        requestLocationIfPossible()
    }

    func stop() {
        hasStarted = false
        configureAutoRefresh(interval: nil)
        weatherRequestGeneration &+= 1
        weatherTask?.cancel()
        weatherTask = nil
        geocoder.cancelGeocode()
        finishLocationUpdate()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus != .notDetermined {
            Self.finishAuthorizationRequest()
        }
        guard hasStarted else { return }
        requestLocationIfPossible()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, Self.isUsable(location) else { return }
        hasUsableLocationForCurrentRequest = true
        Self.persist(location)
        finishLocationUpdate()
        loadWeather(for: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError, clError.code == .locationUnknown {
            return
        }

        finishLocationUpdate()
        guard !hasUsableLocationForCurrentRequest, !snapshot.isLive else { return }
        updateSnapshot(
            WeatherSnapshot(
                temperature: nil,
                apparentTemperature: nil,
                humidity: nil,
                condition: "无法定位",
                locationName: "当前位置",
                symbolName: "exclamationmark.triangle.fill",
                detail: "请开启 Wi-Fi 后重试",
                isLive: false
            )
        )
    }

    private func requestLocationIfPossible() {
        guard CLLocationManager.locationServicesEnabled() else {
            updateSnapshot(
                WeatherSnapshot(
                    temperature: nil,
                    apparentTemperature: nil,
                    humidity: nil,
                    condition: "定位关闭",
                    locationName: "当前位置",
                    symbolName: "location.slash.fill",
                    detail: "请在系统设置中开启定位",
                    isLive: false
                )
            )
            return
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            guard Self.claimAuthorizationRequest() else { return }
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            beginLocationUpdate()
        case .denied, .restricted:
            updateSnapshot(
                WeatherSnapshot(
                    temperature: nil,
                    apparentTemperature: nil,
                    humidity: nil,
                    condition: "未授权",
                    locationName: "当前位置",
                    symbolName: "location.slash.fill",
                    detail: "请允许 NookFlow 访问定位",
                    isLive: false
                )
            )
        @unknown default:
            updateSnapshot(
                WeatherSnapshot(
                    temperature: nil,
                    apparentTemperature: nil,
                    humidity: nil,
                    condition: "不可用",
                    locationName: "当前位置",
                    symbolName: "questionmark.circle.fill",
                    detail: "无法读取定位状态",
                    isLive: false
                )
            )
        }
    }

    private func beginLocationUpdate() {
        guard !isLocationUpdateActive else { return }

        hasUsableLocationForCurrentRequest = useCachedLocationIfAvailable()
        isLocationUpdateActive = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.startUpdatingLocation()

        locationTimeoutTimer?.invalidate()
        let timer = Timer(timeInterval: Self.locationTimeout, repeats: false) { [weak self] _ in
            guard let self, self.isLocationUpdateActive else { return }
            self.finishLocationUpdate()
            guard !self.hasUsableLocationForCurrentRequest, !self.snapshot.isLive else { return }
            self.updateSnapshot(
                WeatherSnapshot(
                    temperature: nil,
                    apparentTemperature: nil,
                    humidity: nil,
                    condition: "无法定位",
                    locationName: "当前位置",
                    symbolName: "exclamationmark.triangle.fill",
                    detail: "请开启 Wi-Fi 后重试",
                    isLive: false
                )
            )
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        locationTimeoutTimer = timer
    }

    private func finishLocationUpdate() {
        locationTimeoutTimer?.invalidate()
        locationTimeoutTimer = nil
        manager.stopUpdatingLocation()
        isLocationUpdateActive = false
    }

    @discardableResult
    private func useCachedLocationIfAvailable() -> Bool {
        let now = Date()
        let location: CLLocation?
        if let systemLocation = manager.location,
           Self.isUsable(systemLocation),
           now.timeIntervalSince(systemLocation.timestamp) <= Self.systemLocationMaxAge {
            location = systemLocation
        } else {
            location = Self.persistedLocation(now: now)
        }

        guard let location else { return false }
        if !snapshot.isLive {
            loadWeather(for: location)
        }
        return true
    }

    private static func isUsable(_ location: CLLocation) -> Bool {
        CLLocationCoordinate2DIsValid(location.coordinate)
            && location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= 50_000
    }

    private static func persist(_ location: CLLocation) {
        let defaults = UserDefaults.standard
        defaults.set(location.coordinate.latitude, forKey: CachedLocationKeys.latitude)
        defaults.set(location.coordinate.longitude, forKey: CachedLocationKeys.longitude)
        defaults.set(location.horizontalAccuracy, forKey: CachedLocationKeys.horizontalAccuracy)
        defaults.set(location.timestamp.timeIntervalSince1970, forKey: CachedLocationKeys.timestamp)
    }

    private static func persistedLocation(now: Date) -> CLLocation? {
        let defaults = UserDefaults.standard
        guard
            defaults.object(forKey: CachedLocationKeys.latitude) != nil,
            defaults.object(forKey: CachedLocationKeys.longitude) != nil,
            defaults.object(forKey: CachedLocationKeys.timestamp) != nil
        else {
            return nil
        }

        let timestamp = Date(
            timeIntervalSince1970: defaults.double(forKey: CachedLocationKeys.timestamp)
        )
        guard now.timeIntervalSince(timestamp) <= persistedLocationMaxAge else { return nil }

        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(
                latitude: defaults.double(forKey: CachedLocationKeys.latitude),
                longitude: defaults.double(forKey: CachedLocationKeys.longitude)
            ),
            altitude: 0,
            horizontalAccuracy: max(0, defaults.double(forKey: CachedLocationKeys.horizontalAccuracy)),
            verticalAccuracy: -1,
            timestamp: timestamp
        )
        return isUsable(location) ? location : nil
    }

    private enum CachedLocationKeys {
        static let latitude = "weather.lastLocation.latitude"
        static let longitude = "weather.lastLocation.longitude"
        static let horizontalAccuracy = "weather.lastLocation.horizontalAccuracy"
        static let timestamp = "weather.lastLocation.timestamp"
    }

    private static func claimAuthorizationRequest() -> Bool {
        authorizationRequestLock.lock()
        defer { authorizationRequestLock.unlock() }

        guard !authorizationRequestInFlight else { return false }
        authorizationRequestInFlight = true
        return true
    }

    private static func finishAuthorizationRequest() {
        authorizationRequestLock.lock()
        authorizationRequestInFlight = false
        authorizationRequestLock.unlock()
    }

    private func loadWeather(for location: CLLocation) {
        weatherRequestGeneration &+= 1
        let requestGeneration = weatherRequestGeneration

        if !snapshot.isLive {
            updateSnapshot(
                WeatherSnapshot(
                    temperature: nil,
                    apparentTemperature: nil,
                    humidity: nil,
                    condition: "加载中",
                    locationName: "当前位置",
                    symbolName: "",
                    detail: "正在更新天气",
                    isLive: false
                )
            )
        }

        weatherTask?.cancel()
        weatherTask = Task { [weak self, location] in
            guard let self else { return }
            do {
                let weatherSnapshot = try await Self.weather(for: location)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self,
                          self.weatherRequestGeneration == requestGeneration
                    else { return }
                    self.lastSuccessfulRefresh = Date()
                    self.snapshot = weatherSnapshot
                    self.resolvePlaceName(
                        for: location,
                        weatherSnapshot: weatherSnapshot,
                        requestGeneration: requestGeneration
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    self?.snapshot = WeatherSnapshot(
                        temperature: nil,
                        apparentTemperature: nil,
                        humidity: nil,
                        condition: "天气不可用",
                        locationName: "当前位置",
                        symbolName: "wifi.exclamationmark",
                        detail: "请检查网络连接",
                        isLive: false
                    )
                }
            }
        }
    }

    private func configureAutoRefresh(interval: TimeInterval?) {
        guard scheduledRefreshInterval != interval else { return }

        refreshTimer?.invalidate()
        refreshTimer = nil
        scheduledRefreshInterval = interval

        guard let interval, interval > 0 else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer.tolerance = min(interval * 0.15, 60)
        refreshTimer = timer
    }

    private func updateSnapshot(_ snapshot: WeatherSnapshot) {
        DispatchQueue.main.async { [weak self] in
            self?.snapshot = snapshot
        }
    }

    private static func weather(for location: CLLocation) async throws -> WeatherSnapshot {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.open-meteo.com"
        components.path = "/v1/forecast"
        components.queryItems = [
            URLQueryItem(
                name: "latitude",
                value: String(
                    format: "%.4f",
                    locale: Locale(identifier: "en_US_POSIX"),
                    location.coordinate.latitude
                )
            ),
            URLQueryItem(
                name: "longitude",
                value: String(
                    format: "%.4f",
                    locale: Locale(identifier: "en_US_POSIX"),
                    location.coordinate.longitude
                )
            ),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m"
            ),
            URLQueryItem(
                name: "daily",
                value: "weather_code,temperature_2m_max,temperature_2m_min"
            ),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "3")
        ]

        guard let url = components.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        let forecast = try JSONDecoder().decode(OpenMeteoForecast.self, from: data)
        let condition = condition(for: forecast.current.weatherCode)

        return WeatherSnapshot(
            temperature: forecast.current.temperature,
            apparentTemperature: forecast.current.apparentTemperature,
            humidity: forecast.current.humidity,
            windSpeed: forecast.current.windSpeed,
            condition: condition.title,
            locationName: "当前位置",
            symbolName: condition.symbolName,
            detail: "体感 \(Int(forecast.current.apparentTemperature.rounded()))° · 湿度 \(forecast.current.humidity)%",
            dailyForecasts: forecast.daily?.summaries() ?? [],
            isLive: true
        )
    }

    private func resolvePlaceName(
        for location: CLLocation,
        weatherSnapshot: WeatherSnapshot,
        requestGeneration: UInt64
    ) {
        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let self else { return }
            let placemark = placemarks?.first
            let name = placemark?.locality
                ?? placemark?.subLocality
                ?? placemark?.administrativeArea
                ?? "当前位置"

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.weatherRequestGeneration == requestGeneration,
                      self.snapshot.isLive
                else { return }
                self.snapshot = weatherSnapshot.merging(locationName: name)
            }
        }
    }

    fileprivate static func condition(for code: Int) -> (title: String, symbolName: String) {
        switch code {
        case 0:
            return ("晴", "sun.max.fill")
        case 1:
            return ("少云", "sun.max.fill")
        case 2:
            return ("多云", "cloud.sun.fill")
        case 3:
            return ("阴", "cloud.fill")
        case 45, 48:
            return ("雾", "cloud.fog.fill")
        case 51, 53, 55:
            return ("毛毛雨", "cloud.drizzle.fill")
        case 56, 57, 66, 67:
            return ("冻雨", "cloud.sleet.fill")
        case 61, 63, 65:
            return ("雨", "cloud.rain.fill")
        case 71, 73, 75, 77:
            return ("雪", "cloud.snow.fill")
        case 80, 81, 82:
            return ("阵雨", "cloud.heavyrain.fill")
        case 85, 86:
            return ("阵雪", "cloud.snow.fill")
        case 95, 96, 99:
            return ("雷雨", "cloud.bolt.rain.fill")
        default:
            return ("天气", "cloud.fill")
        }
    }
}

private extension WeatherSnapshot {
    func merging(locationName: String) -> WeatherSnapshot {
        WeatherSnapshot(
            temperature: temperature,
            apparentTemperature: apparentTemperature,
            humidity: humidity,
            windSpeed: windSpeed,
            condition: condition,
            locationName: locationName,
            symbolName: symbolName,
            detail: detail,
            dailyForecasts: dailyForecasts,
            isLive: isLive
        )
    }
}

private struct OpenMeteoForecast: Decodable {
    let current: OpenMeteoCurrent
    let daily: OpenMeteoDaily?
}

private struct OpenMeteoCurrent: Decodable {
    let temperature: Double
    let humidity: Int
    let apparentTemperature: Double
    let windSpeed: Double
    let weatherCode: Int

    enum CodingKeys: String, CodingKey {
        case temperature = "temperature_2m"
        case humidity = "relative_humidity_2m"
        case apparentTemperature = "apparent_temperature"
        case windSpeed = "wind_speed_10m"
        case weatherCode = "weather_code"
    }
}

private struct OpenMeteoDaily: Decodable {
    let time: [String]
    let weatherCode: [Int]
    let temperatureMax: [Double]
    let temperatureMin: [Double]

    enum CodingKeys: String, CodingKey {
        case time
        case weatherCode = "weather_code"
        case temperatureMax = "temperature_2m_max"
        case temperatureMin = "temperature_2m_min"
    }

    func summaries() -> [WeatherDailySummary] {
        let count = min(time.count, weatherCode.count, temperatureMax.count, temperatureMin.count, 3)
        guard count > 0 else { return [] }

        return (0..<count).map { index in
            let condition = WeatherProvider.condition(for: weatherCode[index])
            let minTemperature = Int(temperatureMin[index].rounded())
            let maxTemperature = Int(temperatureMax[index].rounded())

            return WeatherDailySummary(
                id: time[index],
                title: Self.title(for: time[index], index: index),
                symbolName: condition.symbolName,
                temperatureRangeText: "\(minTemperature)/\(maxTemperature)°"
            )
        }
    }

    private static func title(for dateString: String, index: Int) -> String {
        if index == 0 { return "今天" }
        if index == 1 { return "明天" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        guard let date = formatter.date(from: dateString) else {
            return "周\(index + 1)"
        }

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "zh_CN")
        weekdayFormatter.dateFormat = "EEE"
        return weekdayFormatter.string(from: date)
    }
}
