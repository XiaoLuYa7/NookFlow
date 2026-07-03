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
    private var weatherTask: Task<Void, Never>?
    private static var hasRequestedAuthorization = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    deinit {
        weatherTask?.cancel()
        geocoder.cancelGeocode()
        manager.stopUpdatingLocation()
        manager.delegate = nil
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        requestLocationIfPossible()
    }

    func refresh() {
        hasStarted = true
        requestLocationIfPossible()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        requestLocationIfPossible()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        loadWeather(for: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        updateSnapshot(
                WeatherSnapshot(
                    temperature: nil,
                    apparentTemperature: nil,
                    humidity: nil,
                    condition: "无法定位",
                    locationName: "当前位置",
                symbolName: "exclamationmark.triangle.fill",
                detail: "请稍后重试",
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
            guard !Self.hasRequestedAuthorization else { return }
            Self.hasRequestedAuthorization = true
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            updateSnapshot(
                WeatherSnapshot(
                    temperature: nil,
                    apparentTemperature: nil,
                    humidity: nil,
                    condition: "未授权",
                    locationName: "当前位置",
                    symbolName: "location.slash.fill",
                    detail: "请允许 L-Nook 访问定位",
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

    private func loadWeather(for location: CLLocation) {
        updateSnapshot(
            WeatherSnapshot(
                temperature: nil,
                apparentTemperature: nil,
                humidity: nil,
                condition: "加载中",
                locationName: "当前位置",
                symbolName: "cloud.fill",
                detail: "正在更新天气",
                isLive: false
            )
        )

        weatherTask?.cancel()
        weatherTask = Task { [location] in
            do {
                async let placeName = Self.placeName(for: location)
                async let weather = Self.weather(for: location)
                let resolvedPlaceName = await placeName
                let weatherSnapshot = try await weather
                let resolvedSnapshot = weatherSnapshot.merging(locationName: resolvedPlaceName)
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    self?.snapshot = resolvedSnapshot
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

        let (data, response) = try await URLSession.shared.data(from: url)

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

    private static func placeName(for location: CLLocation) async -> String {
        await withCheckedContinuation { continuation in
            CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
                let placemark = placemarks?.first
                let name = placemark?.locality
                    ?? placemark?.subLocality
                    ?? placemark?.administrativeArea
                    ?? "当前位置"
                continuation.resume(returning: name)
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
