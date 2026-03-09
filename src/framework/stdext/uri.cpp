#include <boost/algorithm/string.hpp>
#include <regex>
#include <algorithm>
#include <cctype>

#include "uri.h"

ParsedURI parseURI(const std::string& url)
{
    ParsedURI result;
    auto value_or = [](const std::string& value, std::string&& deflt) -> std::string {
        return (value.empty() ? deflt : value);
    };
    // Trim leading/trailing whitespace so URLs from config/Lua don't fail
    std::string trimmed;
    trimmed.reserve(url.size());
    size_t start = 0;
    while (start < url.size() && (std::isspace(static_cast<unsigned char>(url[start]))))
        ++start;
    size_t end = url.size();
    while (end > start && (std::isspace(static_cast<unsigned char>(url[end - 1]))))
        --end;
    if (start < end)
        trimmed = url.substr(start, end - start);
    else
        trimmed = url;
    // Note: only "http", "https", "ws", and "wss" protocols are supported. Path is optional.
    static const std::regex PARSE_URL{ R"((([httpsw]{2,5})://)?([^/ :]+)(:(\d+))?(/(.*))?)",
                                       std::regex_constants::ECMAScript | std::regex_constants::icase };
    std::smatch match;
    if (std::regex_match(trimmed, match, PARSE_URL) && match.size() >= 6) {
        result.protocol = value_or(boost::algorithm::to_lower_copy(std::string(match[2].str())), "http");
        result.domain = match[3].str();
        const bool is_sequre_protocol = (result.protocol == "https" || result.protocol == "wss");
        result.port = value_or(match[5].str(), (is_sequre_protocol) ? "443" : "80");
        if (match[6].matched && match[6].length() > 0)
            result.query = "/" + match[6].str();
        else
            result.query = "/";
    }
    return result;
}