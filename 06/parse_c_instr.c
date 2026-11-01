#include "parse_c_instr.h"

#include <stdio.h>
#include <stdlib.h>

void parse_c_intruction(char *line, char **dest, char **comp, char **jump) {
	*dest = "null";
	*jump = "null";

	char *equal_sign, *semicolon;

	equal_sign = strchr(line, '=');
	semicolon = strchr(line, ';');

	if (equal_sign) {
		*equal_sign = '\0';
		if (line[0] == '\0') {
			fprintf(stderr, "Invalid C-instruction: missing dest\n");
			exit(1);
		}
		*dest = line;
		*comp = equal_sign + 1;
	} else {
		*comp = line;
	}
	if (semicolon) {
		*semicolon = '\0';
		if (*(semicolon + 1) == '\0') {
			fprintf(stderr, "Invalid C-instruction: missing jump\n");
			exit(1);
		}
		*jump = semicolon + 1;
	}
	if ((*comp)[0] == '\0') {
		fprintf(stderr, "Invalid C-instruction: missing comp\n");
		exit(1);
	}
}