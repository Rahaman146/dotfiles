#define _POSIX_C_SOURCE 200809L

#include "network.h"
#include "chapter_controller.h"

#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <curl/curl.h>
#include <cjson/cJSON.h>
#include <ncurses.h>
#include <ctype.h>

/**
 * Creates a centered window for displaying chapter content.
 * 
 * @return A new ncurses WINDOW pointer centered on the screen
 */
WINDOW* create_chapter_window() {
  int max_y, max_x;
  getmaxyx(stdscr, max_y, max_x);

  return newwin(CHAPTER_WINDOW_HEIGHT, CHAPTER_WINDOW_WIDTH, (max_y - CHAPTER_WINDOW_HEIGHT) / 2,  (max_x - CHAPTER_WINDOW_WIDTH) / 2);
}

/**
 * Displays a paginated list of chapters in the terminal UI.
 * 
 * @param chapters Array of chapter slugs/URLs
 * @param total Total number of chapters
 * @param offset Current scroll offset (first visible chapter)
 * @param highlight Currently highlighted chapter index
 * @param novel_title Title of the novel to display in header
 */
void display_chapter_list(char chapters[3500][128], int total, int offset, int highlight, const char* novel_title) {

  clear();
  int rows, cols;
  getmaxyx(stdscr, rows, cols);
  (void) cols; // Unused variable

  // Display header with novel title and chapter count
  attron(COLOR_PAIR(4));
  mvprintw(0, 0, "📖 %s CHAPTERS (%d/%d total)", novel_title, total, total); 
  attroff(COLOR_PAIR(4));
  attron(COLOR_PAIR(5) | A_DIM);
  mvprintw(1, 0, "═══════════════════════════════════════════════════════════════");
  attroff(COLOR_PAIR(5) | A_DIM);

  // Calculate which chapters to display on screen
  int start = offset;
  int end = offset + CHAPTERS_VISIBLE;
  if (end > total) end = total;
  int row = 0;

  // Display visible chapters with highlighting for selected chapter
  for (int i = start; i < end; i++) {
    row = 3 + (i - start);
    if (i == highlight) {
      attron(COLOR_PAIR(5) | A_DIM);
      mvprintw(row, 0, "➤ %4d: %s", i+1, chapters[i]);
      attroff(COLOR_PAIR(5) | A_DIM);
    } else {
      mvprintw(row, 0, "  %4d: %s", i+1, chapters[i]);
    }
  }

  // Display bottom border and controls
  attron(COLOR_PAIR(5) | A_DIM);
  mvprintw(row + 2, 0, "═══════════════════════════════════════════════════════════════");
  attroff(COLOR_PAIR(5) | A_DIM);

  attron(COLOR_PAIR(4));
  mvprintw(rows - 1, 2, "↑↓ Move   / Search Chapter   q Back   Enter Open");
  attroff(COLOR_PAIR(4));
  move(21, 0);
  refresh();
}

/**
 * Main chapter browser interface - handles navigation and chapter selection.
 * 
 * @param chapters Array of chapter slugs/URLs for fetching content
 * @param chapter_titles Array of chapter titles for display
 * @param total Total number of chapters
 * @param novel_title Novel title for display
 * @param novel_slug Novel slug (unused)
 * @return -1 when user exits back to previous screen
 */
int show_chapter_browser(char chapters[3500][128], char chapter_titles[3500][128], int total, const char* novel_title, const char* novel_slug __attribute__((unused))) {
  int offset = 0;      // Scroll position
  int highlight = 0;   // Selected chapter

  // Main navigation loop
  while (1) {
    display_chapter_list(chapter_titles, total, offset, highlight, novel_title);

    int ch = getch();
    switch (ch) {
      // Navigate up one chapter
      case KEY_UP:
        if (highlight > 0) highlight--;
        if (highlight < offset) offset = highlight;
        break;

      // Navigate down one chapter
      case KEY_DOWN:
        if (highlight < total - 1) highlight++;
        if (highlight >= offset + CHAPTERS_VISIBLE) offset++;
        break;

      // Page Up - jump up by one screen of chapters
      case KEY_PPAGE:
        offset -= CHAPTERS_VISIBLE; if (offset < 0) offset = 0; highlight = offset; break;

      // Page Down - jump down by one screen of chapters
      case KEY_NPAGE:
        offset += CHAPTERS_VISIBLE; 
        if (offset > total - CHAPTERS_VISIBLE) offset = total - CHAPTERS_VISIBLE;
        highlight = offset; 
        break;

      // Search/Jump to chapter by number
      case '/': {
        echo(); 
        attron(COLOR_PAIR(4));
        mvprintw(21, 0, "Enter chapter: "); 
        attroff(COLOR_PAIR(4));
        refresh();
        char search_buf[16]; getnstr(search_buf, 15); noecho();
        int target = atoi(search_buf);
        if (target > 0 && target <= total) {
          offset = target - 5; if (offset < 0) offset = 0;
          highlight = target - 1;
        }
        break;
      }

      // Enter key - fetch and display chapter content
      case 10: { // Enter key
        int nav_status = 0;
        do {
          char* chapter_html = fetch_chapter_content(chapters[highlight]);

          if (chapter_html && strlen(chapter_html) > 1000) {
            // Get navigation intent from the reader window
            nav_status = display_chapter_content(novel_title, highlight + 1, chapter_html);
            free(chapter_html);

            if (nav_status == 1 && highlight < total - 1) { 
              highlight++; // Move to next chapter
              if (highlight >= offset + CHAPTERS_VISIBLE) offset++;
            } 
            else if (nav_status == -1 && highlight > 0) {
              highlight--; // Move to previous chapter
              if (highlight < offset) offset = highlight;
            }
            else {
              nav_status = 0; // Exit to chapter list
            }
          } else {
            mvprintw(20, 0, "❌ Failed to fetch chapter!");
            refresh(); getch();
            nav_status = 0;
          }
        } while (nav_status != 0); // Keep looping if user navigated
        break;
      }

      // Quit back to novel list
      case 'q': case 'Q': case KEY_LEFT:
        return -1;
    }
  }
}

/**
 * Extracts text from all id="chapterText" divs in HTML.
 * 
 * @param html HTML string to parse
 * @param output Buffer to store extracted text
 * @param max_size Maximum size of output buffer
 */

// Helper to decode basic HTML entities inline
char decode_entity(const char **src) {
    // 1. Handle Hexadecimal: &#x27;
    if (strncmp(*src, "&#x", 3) == 0) {
        char *endptr;
        long val = strtol(*src + 3, &endptr, 16);
        if (*endptr == ';') {
            *src = endptr; // Move src pointer to the semicolon
            return (char)val;
        }
    }
    
    // 2. Handle Decimal: &#39;
    if (strncmp(*src, "&#", 2) == 0 && isdigit((*src)[2])) {
        char *endptr;
        long val = strtol(*src + 2, &endptr, 10);
        if (*endptr == ';') {
            *src = endptr;
            return (char)val;
        }
    }

    // 3. Handle Named Entities (Existing logic)
    if (strncmp(*src, "&lt;", 4) == 0)    { *src += 3; return '<'; }
    if (strncmp(*src, "&gt;", 4) == 0)    { *src += 3; return '>'; }
    if (strncmp(*src, "&amp;", 5) == 0)   { *src += 4; return '&'; }
    if (strncmp(*src, "&quot;", 6) == 0)  { *src += 5; return '"'; }
    if (strncmp(*src, "&apos;", 6) == 0)  { *src += 5; return '\''; }
    if (strncmp(*src, "&nbsp;", 6) == 0)  { *src += 5; return ' '; }

    return **src;
}

int display_chapter_content(const char* novel_title, int chapter_num, const char* html) {
  if (!html) return 1;

  int max_y, max_x;
  getmaxyx(stdscr, max_y, max_x);
  int width = max_x - 4; // Margin

  // --- STEP 1: Extract & Clean Text ---
  // Allocate a buffer (same size as HTML is safe)
  char *clean_text = calloc(strlen(html) + 1, 1);
  char *dst = clean_text;
  const char *cursor = html;

  while ((cursor = strstr(cursor, "id=\"chapterText\""))) {
    // Find text content between '>' and '<'
    const char *start = strchr(cursor, '>');
    if (!start) break;
    start++; // Move past '>'

    const char *end = strchr(start, '<');
    if (!end) break; // formatting error

    // Process this block: Collapse spaces + Decode entities
    int space_pending = 0;
    for (const char *p = start; p < end; p++) {
      if (isspace(*p)) {
        if (dst > clean_text) space_pending = 1; // Mark potential space
      } else {
        // If we skipped spaces previously, insert ONE space now
        if (space_pending && *(dst-1) != '\n') *dst++ = ' ';
        space_pending = 0;

        if (*p == '&') *dst++ = decode_entity(&p);
        else *dst++ = *p;
      }
    }

    // Add paragraph break (double newline)
    if (dst > clean_text && *(dst-1) != '\n') {
      *dst++ = '\n'; 
      *dst++ = '\n';
    }
    cursor = end;
  }
  *dst = '\0';

  // --- STEP 2: Word Wrap into Line List ---
  int line_cap = 1000;
  int n_lines = 0;
  char **lines = malloc(line_cap * sizeof(char*));
  char *ptr = clean_text;

  while (*ptr) {
    if (n_lines >= line_cap) lines = realloc(lines, (line_cap *= 2) * sizeof(char*));

    // Handle paragraph breaks (empty lines)
    if (*ptr == '\n') {
      lines[n_lines++] = strdup(""); 
      ptr++;
      continue;
    }

    // Find where to cut the line
    int len = 0;
    char *line_start = ptr;

    // Greedily grab characters until width or newline
    while (*ptr && *ptr != '\n' && len < width) {
      ptr++;
      len++;
    }

    // Backtrack to the last space if we split a word in the middle
    if (*ptr && *ptr != '\n' && !isspace(*ptr)) {
      int back_steps = 0;
      char *temp = ptr;
      while (back_steps < len && !isspace(*temp)) {
        temp--; back_steps++;
      }
      // If we found a space, cut there. If not (giant word), keep the split.
      if (back_steps < len) {
        ptr = temp;
        len -= back_steps;
      }
    }

    // Copy this line
    lines[n_lines] = malloc(len + 1);
    strncpy(lines[n_lines], line_start, len);
    lines[n_lines][len] = '\0';
    n_lines++;

    // Skip the space/newline we just broke on
    if (isspace(*ptr)) ptr++;
  }

  // --- STEP 3: Display Loop ---
  int scroll = 0;
  int ch = 0;
  int content_h = max_y - 4; // Reserve space for header/footer

  while (ch != 'q' && ch != KEY_LEFT) {
    clear();

    // Display header
    attron(COLOR_PAIR(4));
    mvprintw(0, 0, "📖 %s - Chapter %d                    Line %d/%d", novel_title, chapter_num, scroll + 1, n_lines);
    attroff(COLOR_PAIR(4));

    attron(COLOR_PAIR(5) | A_DIM);
    mvprintw(1, 0, "════════════════════════════════════════════════════════════════════");
    attroff(COLOR_PAIR(5) | A_DIM);

    // Body
    for (int i = 0; i < content_h; i++) {
      int line_idx = scroll + i;
      if (line_idx < n_lines) {
        mvprintw(i + 2, 2, "%s", lines[line_idx]);
      }
    }

    // Display footer
    attron(COLOR_PAIR(5) | A_DIM);
    mvprintw(max_y - 2, 0, "════════════════════════════════════════════════════════════════════");
    attroff(COLOR_PAIR(5) | A_DIM);

    attron(COLOR_PAIR(4));
    mvprintw(max_y - 1, 2, "← Prev Chap   → Next Chap   ↑↓ Scroll   PgUp/PgDn Page ↑↓   q Back");
    attroff(COLOR_PAIR(4));

    refresh();
    ch = getch();

    if (ch == 'q' || ch == 'Q') return 0;
    else if (ch == KEY_LEFT) return -1;
    else if (ch == KEY_RIGHT) return 1;
    else if (ch == KEY_UP && scroll > 0) scroll--;
    else if (ch == KEY_DOWN && scroll < n_lines - content_h) scroll++;
    else if (ch == KEY_PPAGE) scroll = (scroll - content_h > 0) ? scroll - content_h : 0;
    else if (ch == KEY_NPAGE) scroll = (scroll + content_h < n_lines - content_h) ? scroll + content_h : n_lines - content_h;
  }

  // Cleanup
  free(clean_text);
  for (int i = 0; i < n_lines; i++) free(lines[i]);
  free(lines);

  return 0;
}
