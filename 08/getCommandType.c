#include "getCommandType.h"

void getCommand(TokenizedLine info, FILE* out, int* counter, int* n_args, char* function_name, char* filename) {
	char* command_token = info.tokens[0];
	const CommandEntry* result = in_table(command_token);
	int cmd_code = result->type;

	if (info.count != result->expected_tokens) {
		fprintf(stderr, "Command structure misalignment\n");
		exit(EXIT_FAILURE);
	}

	switch(cmd_code) {
		//Arithmetic/Logical Operations
		case C_ADD:
		case C_SUB:
		case C_AND:
		case C_OR:
		case C_NEG:
		case C_NOT:
		case C_EQ:
		case C_LT:
		case C_GT:
			write_arithmetic(out, cmd_code, counter);
			break;
		//Push/Pop Stack Operations
		case C_POP:
		case C_PUSH: {
			char* segment = info.tokens[1];
			int offset = string_to_int(info.tokens[2]);
			write_memory_access(out, cmd_code, segment, &offset, filename);
			break;
		}
		//Labelling Operation
		case C_LABEL:{
			char* label = info.tokens[1];
			write_label(out, function_name, label);
			break;
		}
		case C_GOTO:{
			char* label = info.tokens[1];
			write_goto(out, function_name, label);
			break;
		}
		case C_IF_GOTO: {
			char* label = info.tokens[1];
			write_ifgoto(out, function_name, label);
			break;
		}
		case C_FUNCTION: {
			size_t size = strlen(info.tokens[1]);
			if (size >= 256) {
				fprintf(stderr, "Error: function name too long\n");
				exit(EXIT_FAILURE);
			}
			memcpy(function_name, info.tokens[1], size + 1);
			*n_args = string_to_int(info.tokens[2]);
			if (*n_args < 0) {
			    fprintf(stderr, "function local count must be non-negative\n");
				exit(EXIT_FAILURE);
			}
			int n_locals = *n_args;
			write_function(out, function_name, n_locals);
			break;
		}
		case C_CALL: {
			char* callee = info.tokens[1];
			int n_args = string_to_int(info.tokens[2]);
			if (n_args < 0) {
			    fprintf(stderr, "call argument count must be non-negative\n");
				exit(EXIT_FAILURE);
			}
			write_call(out, function_name, callee, n_args, counter);
			break;
		}
		case C_RETURN: {
			write_return(out);
			break;
		}
	}
}
