#include <stdio.h>
#include <stdlib.h>

#include "tokenizer.h"

int main(int argc, char **argv) {
  if (argc != 2) {
    fprintf(stderr, "Usage: %s <input.jack>\n", argv[0]);
    return EXIT_FAILURE;
  }

  FILE *input = fopen(argv[1], "rb");
  if (!input) {
    perror("Could not open input");
    return EXIT_FAILURE;
  }

  if (fseek(input, 0, SEEK_END) != 0) {
    perror("Could not seek input");
    fclose(input);
    return EXIT_FAILURE;
  }

  long file_size = ftell(input);
  if (file_size < 0 || fseek(input, 0, SEEK_SET) != 0) {
    perror("Could not determine input size");
    fclose(input);
    return EXIT_FAILURE;
  }

  char *source = malloc((size_t)file_size + 1);
  Token *tokens = calloc(256, sizeof(*tokens));
  if (!source || !tokens) {
    fprintf(stderr, "Could not allocate tokenizer input\n");
    free(source);
    free(tokens);
    fclose(input);
    return EXIT_FAILURE;
  }

  size_t bytes_read = fread(source, 1, (size_t)file_size, input);
  fclose(input);
  if (bytes_read != (size_t)file_size) {
    fprintf(stderr, "Could not read complete input\n");
    free(source);
    free(tokens);
    return EXIT_FAILURE;
  }
  source[bytes_read] = '\0';

  TokenTable table = {.tokens = tokens, .capacity = 256, .count = 0};
  tokenizer(&table, source);
  print_tokenizer_xml(stdout, &table);

  free(tokens);
  free(source);
  return EXIT_SUCCESS;
}
