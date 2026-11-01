#include <dirent.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "parser.h"

int is_jack_file(const char *filename) {
  size_t len = strlen(filename);
  return (len > 5 && strcmp(filename + len - 5, ".jack") == 0);
}

char *read_file_to_buffer(const char *filename) {
  FILE *file = fopen(filename, "rb");
  if (!file) {
    fprintf(stderr, "Fatal Error: Could not open file %s\n", filename);
    exit(EXIT_FAILURE);
  }

  if (fseek(file, 0, SEEK_END) != 0) {
    fprintf(stderr, "Fatal Error: Failed to seek file %s\n", filename);
    fclose(file);
    exit(EXIT_FAILURE);
  }
  long length = ftell(file);
  if (length < 0) {
    fprintf(stderr, "Fatal Error: Failed to determine file length for %s\n",
            filename);
    fclose(file);
    exit(EXIT_FAILURE);
  }
  if (fseek(file, 0, SEEK_SET) != 0) {
    fprintf(stderr, "Fatal Error: Failed to rewind file %s\n", filename);
    fclose(file);
    exit(EXIT_FAILURE);
  }

  char *buffer = malloc(length + 1);
  if (!buffer) {
    fprintf(stderr, "Fatal Error: Memory allocation failed for file buffer\n");
    exit(EXIT_FAILURE);
  }

  size_t expected = (size_t)length;
  size_t read_bytes = fread(buffer, 1, expected, file);
  if (read_bytes != expected) {
      fprintf(stderr, "Fatal Error: Failed to read entire file %s\n", filename);
      fclose(file);
      free(buffer);
      exit(EXIT_FAILURE);
  }
  buffer[expected] = '\0';
  fclose(file);
  return buffer;
}

void compile_single_file(const char *input_path, const char *base_name) {
  char *source_buffer = read_file_to_buffer(input_path);

  TokenTable table;
  table.capacity = 256;
  table.count = 0;
  table.tokens = malloc(sizeof(Token) * table.capacity);
  if (!table.tokens) {
    fprintf(stderr, "Fatal Error: Failed to allocate Token table\n");
    free(source_buffer);
    exit(EXIT_FAILURE);
  }

  /* Construct both output paths from the base name (no extension) */
  char xml_path[1024];
  snprintf(xml_path, sizeof(xml_path), "%s.xml", base_name);

  FILE *xml_out = fopen(xml_path, "w");
  if (!xml_out) {
    fprintf(stderr, "Fatal Error: Could not open output file %s\n", xml_path);
    free(table.tokens);
    free(source_buffer);
    exit(EXIT_FAILURE);
  }

  ParserState p;
  p.table = &table;
  p.current = 0;
  p.out = xml_out;

  printf("Parsing: %s -> %s\n", input_path, xml_path);

  parser(&p, source_buffer);

  fclose(xml_out);
  free(table.tokens);
  free(source_buffer);
}

int main(int argc, char *argv[]) {
  if (argc < 2) {
    fprintf(stderr, "Usage: %s <input_file.jack | input_directory>\n", argv[0]);
    return EXIT_FAILURE;
  }

  const char *target_path = argv[1];
  struct stat path_stat;

  if (stat(target_path, &path_stat) != 0) {
    fprintf(stderr, "Fatal Error: Path '%s' does not exist.\n", target_path);
    return EXIT_FAILURE;
  }

  if (S_ISREG(path_stat.st_mode)) {
    if (!is_jack_file(target_path)) {
      fprintf(stderr, "Error: Target file must have a .jack extension.\n");
      return EXIT_FAILURE;
    }

    /* Strip .jack to get base name */
    char base_name[512];
    size_t len = strlen(target_path);
    snprintf(base_name, sizeof(base_name), "%.*s", (int)(len - 5), target_path);

    compile_single_file(target_path, base_name);

  } else if (S_ISDIR(path_stat.st_mode)) {
    DIR *dir = opendir(target_path);
    if (!dir) {
      fprintf(stderr, "Fatal Error: Could not open directory %s\n",
              target_path);
      return EXIT_FAILURE;
    }

    struct dirent *entry;
    while ((entry = readdir(dir)) != NULL) {
      if (is_jack_file(entry->d_name)) {
        char input_filepath[1024];
        char base_name[1024];

        snprintf(input_filepath, sizeof(input_filepath), "%s/%s", target_path,
                 entry->d_name);

        size_t file_len = strlen(entry->d_name);
        snprintf(base_name, sizeof(base_name), "%s/%.*s", target_path,
                 (int)(file_len - 5), entry->d_name);

        compile_single_file(input_filepath, base_name);
      }
    }
    closedir(dir);

  } else {
    fprintf(stderr, "Error: Unsupported path type.\n");
    return EXIT_FAILURE;
  }

  printf("All files processed successfully.\n");
  return EXIT_SUCCESS;
}
