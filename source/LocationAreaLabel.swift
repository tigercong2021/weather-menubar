import Foundation

/// Builds a coarse weather label only from structured geocoder fields.
/// Never pass a formatted address, POI name, street or house number to this formatter.
enum LocationAreaLabel {
    static func displayName(city: String?, subLocality: String?, subAdministrativeArea: String?,
                            administrativeArea: String?, countryCode: String?, allowDistrict: Bool = true) -> String? {
        let city = safeComponent(city)
        let subLocality = safeComponent(subLocality)
        let subAdministrativeArea = safeComponent(subAdministrativeArea)
        let administrativeArea = safeComponent(administrativeArea)
        let isChina = countryCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "CN"

        if isChina {
            let municipalities: Set<String> = ["北京", "上海", "天津", "重庆"]
            let municipality = administrativeArea.map(chineseCityName).flatMap {
                municipalities.contains($0) ? $0 : nil
            }
            // A municipality can appear as the province while locality contains its district.
            // In ordinary provinces, subAdministrativeArea may instead be the prefecture city.
            let parentCity = [subAdministrativeArea, administrativeArea].compactMap { $0 }.first {
                $0.hasSuffix("市") && !isChineseDistrict($0)
            }
            let cityIsDistrict = city.map(isChineseDistrict) ?? false
            let base = municipality
                ?? (cityIsDistrict ? parentCity : city)
                ?? parentCity
            // A distinct city-level name inside subLocality can be a county-level city
            // (for example 苏州 / 昆山市); never infer that from a parent subAdministrativeArea.
            let lowerCity = subLocality.flatMap { value in
                value.hasSuffix("市") && !same(value, base, isChina: true) ? value : nil
            }
            let district = [subLocality, cityIsDistrict ? city : nil, subAdministrativeArea]
                .compactMap { $0 }
                .first { isChineseDistrict($0) && !same($0, base, isChina: true) }
            if let base { return joined(chineseCityName(base), allowDistrict ? district ?? lowerCity : nil, isChina: true) }
            if !allowDistrict {
                return [city, administrativeArea, subAdministrativeArea].compactMap { $0 }
                    .first { !isChineseDistrict($0) }
            }
            return district ?? city ?? administrativeArea ?? subAdministrativeArea
        }

        // Overseas subLocality can be a borough or neighborhood. A county is often
        // the city's parent, so never append subAdministrativeArea as a faux borough.
        let base = city ?? subAdministrativeArea ?? administrativeArea
        guard let base else { return allowDistrict ? subLocality : nil }
        return joined(base, allowDistrict ? subLocality : nil, isChina: false)
    }

    private static func joined(_ city: String, _ detail: String?, isChina: Bool) -> String {
        guard let detail, !same(city, detail, isChina: isChina) else { return city }
        return city + "·" + detail
    }

    private static func same(_ first: String, _ second: String?, isChina: Bool) -> Bool {
        guard let second else { return false }
        let lhs = isChina ? chineseCityName(first) : first
        let rhs = isChina ? chineseCityName(second) : second
        return lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    private static func chineseCityName(_ value: String) -> String {
        value.hasSuffix("市") && value.count > 1 ? String(value.dropLast()) : value
    }

    private static func isChineseDistrict(_ value: String) -> Bool {
        guard value.count > 1,
              ["区", "县", "旗"].contains(where: value.hasSuffix),
              !["市辖区", "市辖县", "辖区"].contains(value),
              !["社区", "小区", "园区", "校区", "厂区", "景区", "住宅区"].contains(where: value.hasSuffix)
        else { return false }
        return true
    }

    private static func safeComponent(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 80, !["市辖区", "市辖县", "辖区"].contains(value),
              value.rangeOfCharacter(from: .controlCharacters) == nil,
              value.rangeOfCharacter(from: CharacterSet(charactersIn: ",，;；/\\\n\r")) == nil,
              !["街道", "乡镇", "门牌", "单元", "公寓", "号", "栋", "室"].contains(where: value.contains),
              !["路", "街", "巷", "弄", "镇", "乡", "村"].contains(where: value.hasSuffix)
        else { return nil }
        // Retain names such as St. Louis, 路北区 and 镇海区; reject recognizable street
        // endings and house-number prefixes without treating every numeral as an address.
        let streetEnding = #"(?i)\s(?:street|st\.?|road|rd\.?|avenue|ave\.?|boulevard|blvd\.?|lane|ln\.?|drive|dr\.?|highway|hwy\.?|way|court|ct\.?)\s*(?:\d+.*)?$"#
        guard value.range(of: streetEnding, options: .regularExpression) == nil,
              value.range(of: #"^\d+\s+\S"#, options: .regularExpression) == nil else { return nil }
        return value
    }
}
