// Copyright Contributors to the OpenDCC project
// SPDX-License-Identifier: Apache-2.0

#include "opendcc/base/fs_utils/glob.h"
#include "opendcc/base/defines.h"
#include "opendcc/base/utils/scope_guard.h"
#include <system_error>
#include <utility>
#ifdef OPENDCC_OS_WINDOWS
#include <algorithm>
#include <filesystem>
#include <Windows.h>
#else
#include <algorithm>
#include <filesystem>
#include <string_view>
#endif

OPENDCC_NAMESPACE_OPEN

namespace base::fs_utils
{

    using base::utils::ScopeGuard;
    namespace
    {
        void add_diagnostic(GlobError& failure, const std::string& path, const std::error_code& error)
        {
            auto code = GlobErrorCode::IO_ERROR;
            if (error == std::errc::permission_denied || error == std::errc::operation_not_permitted)
                code = GlobErrorCode::PERMISSION_DENIED;
            else if (error == std::errc::not_enough_memory)
                code = GlobErrorCode::OUT_OF_MEMORY;
            failure.diagnostics.push_back({ code, path, error });
        }
    }

#ifdef OPENDCC_OS_WINDOWS
    namespace
    {
        void report_error(const std::filesystem::path& path, const std::error_code& error, GlobError& failure)
        {
            if (error && error != std::errc::no_such_file_or_directory && error != std::errc::not_a_directory)
            {
                const auto utf8_path = path.generic_u8string();
                add_diagnostic(failure, std::string(utf8_path.begin(), utf8_path.end()), error);
            }
        }
    }

#else
    namespace
    {
        // glob(3) is not a stable definition to build on: the macOS implementation has no POSIX character classes,
        // and its case-insensitive default filesystem makes a literal segment match either case, so identical
        // patterns answer differently per platform. Matching a path segment is therefore defined here, with the
        // semantics the tests specify, instead of delegated to the C library.
        using CodePoints = std::u32string;

        CodePoints decode_utf8(std::string_view text)
        {
            CodePoints points;
            points.reserve(text.size());
            for (size_t index = 0; index < text.size();)
            {
                const auto lead = static_cast<unsigned char>(text[index]);
                size_t length = 1;
                char32_t value = lead;
                if ((lead & 0x80) == 0)
                    length = 1;
                else if ((lead & 0xE0) == 0xC0)
                {
                    length = 2;
                    value = lead & 0x1F;
                }
                else if ((lead & 0xF0) == 0xE0)
                {
                    length = 3;
                    value = lead & 0x0F;
                }
                else if ((lead & 0xF8) == 0xF0)
                {
                    length = 4;
                    value = lead & 0x07;
                }
                if (length > text.size() - index)
                {
                    // Truncated sequence: treat the byte as-is rather than failing the whole match.
                    points.push_back(lead);
                    ++index;
                    continue;
                }
                for (size_t extra = 1; extra < length; ++extra)
                    value = (value << 6) | (static_cast<unsigned char>(text[index + extra]) & 0x3F);
                points.push_back(value);
                index += length;
            }
            return points;
        }

        bool class_matches(std::string_view name, char32_t character)
        {
            const bool is_upper = character >= U'A' && character <= U'Z';
            const bool is_lower = character >= U'a' && character <= U'z';
            const bool is_digit = character >= U'0' && character <= U'9';
            if (name == "alpha")
                return is_upper || is_lower;
            if (name == "digit")
                return is_digit;
            if (name == "alnum")
                return is_upper || is_lower || is_digit;
            if (name == "upper")
                return is_upper;
            if (name == "lower")
                return is_lower;
            if (name == "xdigit")
                return is_digit || (character >= U'a' && character <= U'f') || (character >= U'A' && character <= U'F');
            if (name == "space")
                return character == U' ' || (character >= U'\t' && character <= U'\r');
            if (name == "blank")
                return character == U' ' || character == U'\t';
            if (name == "punct")
                return character > 32 && character < 127 && !is_upper && !is_lower && !is_digit;
            if (name == "print")
                return character >= 32 && character < 127;
            if (name == "graph")
                return character > 32 && character < 127;
            if (name == "cntrl")
                return character < 32 || character == 127;
            return false;
        }

        // One path segment: '*' and '?' wildcards, a literal '\' escape, and bracket expressions including POSIX
        // classes such as [[:alpha:]].
        bool match_segment(std::string_view name, std::string_view pattern)
        {
            const auto text = decode_utf8(name);
            const auto mask = decode_utf8(pattern);
            size_t ti = 0;
            size_t mi = 0;
            size_t star_mask = CodePoints::npos;
            size_t star_text = 0;
            while (ti < text.size())
            {
                const bool mask_left = mi < mask.size();
                if (mask_left && mask[mi] == U'\\' && mi + 1 < mask.size())
                {
                    if (text[ti] == mask[mi + 1])
                    {
                        ti += 1;
                        mi += 2;
                        continue;
                    }
                }
                else if (mask_left && mask[mi] == U'*')
                {
                    star_mask = mi++;
                    star_text = ti;
                    continue;
                }
                else if (mask_left && (mask[mi] == U'?' || mask[mi] == U'['))
                {
                    if (mask[mi] == U'?')
                    {
                        ++ti;
                        ++mi;
                        continue;
                    }
                    // Bracket expression: optional '!'/'^', ranges, and [[:class:]] entries.
                    size_t cursor = mi + 1;
                    bool negated = false;
                    if (cursor < mask.size() && (mask[cursor] == U'!' || mask[cursor] == U'^'))
                    {
                        negated = true;
                        ++cursor;
                    }
                    bool matched = false;
                    bool closed = false;
                    while (cursor < mask.size())
                    {
                        if (mask[cursor] == U']')
                        {
                            closed = true;
                            ++cursor;
                            break;
                        }
                        if (mask[cursor] == U'[' && cursor + 1 < mask.size() && mask[cursor + 1] == U':')
                        {
                            const auto class_end = mask.find(U":]", cursor + 2);
                            if (class_end == CodePoints::npos)
                                return false;
                            std::string class_name;
                            for (size_t index = cursor + 2; index < class_end; ++index)
                                class_name.push_back(static_cast<char>(mask[index]));
                            matched = matched || class_matches(class_name, text[ti]);
                            cursor = class_end + 2;
                            continue;
                        }
                        if (cursor + 2 < mask.size() && mask[cursor + 1] == U'-' && mask[cursor + 2] != U']')
                        {
                            matched = matched || (text[ti] >= mask[cursor] && text[ti] <= mask[cursor + 2]);
                            cursor += 3;
                            continue;
                        }
                        matched = matched || text[ti] == mask[cursor];
                        ++cursor;
                    }
                    if (!closed)
                        return false;
                    if (matched != negated)
                    {
                        ++ti;
                        mi = cursor;
                        continue;
                    }
                }
                else if (mask_left && text[ti] == mask[mi])
                {
                    ++ti;
                    ++mi;
                    continue;
                }
                // No match here: give back one character to the last '*' and retry.
                if (star_mask == CodePoints::npos)
                    return false;
                mi = star_mask + 1;
                ti = ++star_text;
            }
            while (mi < mask.size() && mask[mi] == U'*')
                ++mi;
            return mi == mask.size();
        }

        bool is_pattern(std::string_view segment)
        {
            return segment.find_first_of("*?[\\") != std::string_view::npos;
        }

        void report_error(const std::filesystem::path& path, const std::error_code& error, GlobError& failure)
        {
            if (error && error != std::errc::no_such_file_or_directory && error != std::errc::not_a_directory)
                add_diagnostic(failure, path.generic_u8string(), error);
        }
    }
#endif

    GlobResult glob_paths(const GlobPaths& patterns)
    {
        GlobError failure;
        GlobPaths result;
#ifdef OPENDCC_OS_WINDOWS
        for (const auto& pattern : patterns)
        {
            if (pattern.empty())
                continue;
            const auto path = std::filesystem::u8path(pattern);
            std::vector<std::filesystem::path> candidates { path.root_path() };
            for (const auto& part : path.relative_path())
            {
                std::vector<std::filesystem::path> next;
                for (const auto& parent : candidates)
                {
                    if (part.native().find_first_of(L"*?") == std::wstring::npos)
                    {
                        next.push_back(parent / part);
                        continue;
                    }
                    const auto directory = parent.empty() ? std::filesystem::path(".") : parent;
                    WIN32_FIND_DATAW data {};
                    const auto handle = FindFirstFileW((directory / part).c_str(), &data);
                    if (handle == INVALID_HANDLE_VALUE)
                    {
                        report_error(directory, std::error_code(GetLastError(), std::system_category()), failure);
                        continue;
                    }
                    const ScopeGuard close_handle([&] { FindClose(handle); });
                    do
                    {
                        next.push_back(parent / data.cFileName);
                    } while (FindNextFileW(handle, &data));
                    const auto find_error = GetLastError();
                    if (find_error != ERROR_NO_MORE_FILES)
                        report_error(directory, std::error_code(find_error, std::system_category()), failure);
                }
                candidates = std::move(next);
            }
            for (const auto& candidate : candidates)
            {
                std::error_code error;
                const auto status = std::filesystem::symlink_status(candidate, error);
                report_error(candidate, error, failure);
                if (error || !std::filesystem::exists(status))
                    continue;
                const auto utf8_path = candidate.generic_u8string();
                std::string value(utf8_path.begin(), utf8_path.end());
                const auto directory = std::filesystem::is_directory(candidate, error);
                report_error(candidate, error, failure);
                if (directory && !value.empty() && value.back() != '/')
                    value += '/';
                result.push_back(std::move(value));
            }
        }
        std::sort(result.begin(), result.end());
#else
        // Paths are accumulated as text, not as std::filesystem::path: lexically_normal would swallow the "." and
        // ".." segments that glob(3) reports verbatim, and those are part of the observed behaviour.
        const auto join_segment = [](std::string& current, std::string_view segment) {
            if (!current.empty() && current.back() != '/')
                current += '/';
            current += segment;
        };
        for (const auto& pattern : patterns)
        {
            if (pattern.empty())
                continue;
            const auto path = std::filesystem::u8path(pattern);
            const auto root = path.root_path().generic_u8string();
            std::vector<std::string> candidates { root };
            for (const auto& part : path.relative_path())
            {
                const auto part_native = part.native();
                if (!is_pattern(part_native))
                {
                    // A literal segment still has to name an existing entry exactly: on a case-insensitive
                    // filesystem "A1" would otherwise resolve to "a1", which glob(3) never reported.
                    std::string plain;
                    for (size_t index = 0; index < part_native.size(); ++index)
                    {
                        if (part_native[index] == '\\' && index + 1 < part_native.size())
                            plain.push_back(part_native[++index]);
                        else
                            plain.push_back(part_native[index]);
                    }
                    const bool relative_dot = plain == "." || plain == "..";
                    std::vector<std::string> next;
                    for (auto& candidate : candidates)
                    {
                        if (!relative_dot)
                        {
                            const auto directory = candidate.empty() ? std::string(".") : candidate;
                            std::error_code probe_error;
                            std::filesystem::directory_iterator probe(directory, probe_error);
                            report_error(directory, probe_error, failure);
                            if (probe_error)
                                continue;
                            bool present = false;
                            for (const auto& entry : probe)
                            {
                                if (entry.path().filename().native() == plain)
                                {
                                    present = true;
                                    break;
                                }
                            }
                            if (!present)
                                continue;
                        }
                        join_segment(candidate, plain);
                        next.push_back(std::move(candidate));
                    }
                    candidates = std::move(next);
                }
                else
                {
                    std::vector<std::string> next;
                    for (const auto& parent : candidates)
                    {
                        const auto directory = parent.empty() ? std::string(".") : parent;
                        std::error_code error;
                        std::filesystem::directory_iterator iterator(directory, error);
                        report_error(directory, error, failure);
                        if (error)
                            continue;
                        std::vector<std::string> names;
                        for (const auto& entry : iterator)
                            names.push_back(entry.path().filename().native());
                        // glob(3) exposes "." and ".." as ordinary entries next to the real ones.
                        names.push_back(".");
                        names.push_back("..");
                        std::sort(names.begin(), names.end());
                        const auto mask = std::string_view(part_native);
                        const bool dot_allowed = !mask.empty() && mask.front() == '.';
                        for (const auto& name : names)
                        {
                            if (!name.empty() && name.front() == '.' && !dot_allowed)
                                continue;
                            if (!match_segment(name, mask))
                                continue;
                            auto candidate = parent;
                            join_segment(candidate, name);
                            next.push_back(std::move(candidate));
                        }
                    }
                    candidates = std::move(next);
                }
            }
            for (const auto& candidate : candidates)
            {
                std::error_code error;
                const auto candidate_path = std::filesystem::u8path(candidate);
                const auto status = std::filesystem::symlink_status(candidate_path, error);
                report_error(candidate, error, failure);
                if (error || !std::filesystem::exists(status))
                    continue;
                auto value = candidate;
                const auto directory = std::filesystem::is_directory(candidate_path, error);
                report_error(candidate, error, failure);
                if (directory && !value.empty() && value.back() != '/')
                    value += '/';
                result.push_back(std::move(value));
            }
        }
        #endif
        if (!failure.diagnostics.empty())
        {
            failure.partial_matches = std::move(result);
            return utils::Unexpected<GlobError>(std::move(failure));
        }
        return result;
    }

}

OPENDCC_NAMESPACE_CLOSE
