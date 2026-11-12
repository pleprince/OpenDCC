/*
 * Copyright Contributors to the OpenDCC project
 * SPDX-License-Identifier: Apache-2.0
 */

#pragma once
#include "opendcc/opendcc.h"
#include "opendcc/base/commands_api/core/args.h"
#include "opendcc/base/commands_api/core/command_syntax.h"
#include <cstring>
#include <typeinfo>

OPENDCC_NAMESPACE_OPEN

namespace base::commands
{

    /** Type equality that survives separate type_info objects for the same type in different images. */
    inline bool same_type(const std::type_info& lhs, const std::type_info& rhs)
    {
        return lhs == rhs || std::strcmp(lhs.name(), rhs.name()) == 0;
    }

    class OPENDCC_BASE_COMMANDS_API CommandResult
    {
    public:
        enum class Status
        {
            SUCCESS,
            FAIL,
            INVALID_SYNTAX,
            INVALID_ARG,
            CMD_NOT_REGISTERED
        };

        CommandResult(Status result = Status::FAIL, std::shared_ptr<CommandArgBase> result_value = nullptr);
        template <class T>
        CommandResult(Status result, const T& result_value)
            : CommandResult(result)
        {
            m_result_value = std::make_shared<CommandArg<std::decay_t<T>>>(result_value);
        }

        operator bool() const;
        bool is_successful() const;
        const std::type_info& get_type_info() const;
        bool has_result() const;
        Status get_status() const;

        template <class T>
        std::shared_ptr<CommandArg<T>> get_result() const
        {
            if (auto typed = std::dynamic_pointer_cast<CommandArg<T>>(m_result_value))
                return typed;
            // A template instantiation such as CommandArg<pybind11::object> gets its own type_info in every image
            // that instantiates it, and macOS does not unify them, so dynamic_cast fails for a value created in
            // another module even though the types are identical. The mangled name is unique per type, so compare
            // that and cast statically.
            if (m_result_value && same_type(m_result_value->get_type_info(), typeid(T)))
                return std::static_pointer_cast<CommandArg<T>>(m_result_value);
            return nullptr;
        }

        std::shared_ptr<CommandArgBase> get_result() const;

        template <class T>
        bool is_holding() const
        {
            return same_type(get_type_info(), typeid(T));
        }

    private:
        std::shared_ptr<CommandArgBase> m_result_value;
        Status m_result = Status::FAIL;
    };

    class OPENDCC_BASE_COMMANDS_API Command
    {
    public:
        Command() = default;
        virtual ~Command() = default;

        virtual CommandResult execute(const CommandArgs& args) = 0;

        CommandSyntax get_syntax() const;
        std::string get_command_name() const;

    protected:
        friend class CommandRegistry;

        std::string m_command_name;
    };

    class OPENDCC_BASE_COMMANDS_API UndoCommand : virtual public Command
    {
    public:
        virtual ~UndoCommand() = default;

        virtual void undo();
        virtual void redo();

        virtual bool merge_with(UndoCommand* command);
    };

    class ToolCommand : virtual public Command
    {
    public:
        virtual CommandArgs make_args() const = 0;
    };

}

OPENDCC_NAMESPACE_CLOSE
