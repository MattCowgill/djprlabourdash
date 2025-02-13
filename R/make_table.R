#' Create a table for the dashboard or a briefing document
#' @param data A data frame containing data to summarise
#' @param destination "dashboard" or "briefing"
#' @param years_in_sparklines Period of time to include in the sparkline line
#' charts.
#' @param row_order Vector of series IDs, in the order in which you wish the
#' corresponding rows to be included in the output table
#' @param highlight_rows Vector of series IDs, corresponding to rows
#' in the table to highlight.
#' Highlighted rows are bolded and have a top border; non-highlighted rows
#' are indented. If `NULL` then all rows are non-bold, non-indented.
#' @param notes Optional notes to add to caption. Source will be inferred
#' automatically based on the data using `caption_auto()`.
#' @param title Character vector to use as the table title. Will only be used
#' when `destination` is "briefing".
#' @param rename_indicators logical; default is `TRUE`. If `TRUE`, the
#' `rename_indicators()` function will be used to rename certain indicators.
#' @param pretty_round Logical; `TRUE` by default. If `TRUE`, figures will be
#' rounded using `pretty_round()`. This means (for eg.) figures below 50
#' will be rounded to 0. If `FALSE`, figures will not be rounded with
#' `pretty_round()`.
#' @examples
#' # dash_data <- load_dash_data()
#' \dontrun{
#' make_table(
#'   data = filter_dash_data(series_ids = c(
#'     "A84423354L",
#'     "A84423242V",
#'     "A84423466F"
#'   )),
#'   row_order = c(
#'     "A84423354L",
#'     "A84423242V",
#'     "A84423466F"
#'   ),
#'   highlight_rows = c("A84426256L")
#' )
#' }
make_table <- function(data,
                       destination = Sys.getenv("R_DJPRLABOURDASH_TABLEDEST",
                         unset = "dashboard"
                       ),
                       years_in_sparklines = 3,
                       row_order = NULL,
                       highlight_rows = NULL,
                       notes = NULL,
                       title = "",
                       rename_indicators = TRUE,
                       pretty_round = TRUE) {
  stopifnot(destination %in% c("dashboard", "briefing"))
  stopifnot(inherits(data, "data.frame"))
  stopifnot(nrow(data) >= 1)

  # Change value of indicator column for specific series IDs
  if (rename_indicators) {
    df <- rename_indicators(data)
  } else {
    df <- data
  }

  # Create a summary dataframe with one row per unique indicator
  summary_df <- create_summary_df(df,
    years_in_sparklines = years_in_sparklines,
    pretty_round = pretty_round
  )

  # Reorder dataframe if row_order is specified
  if (!is.null(row_order)) {
    # Check that all series IDs in the data are in `row_order`
    if (!all(summary_df$series_id %in% row_order)) {
      stop("`row_order` was specified, but not all series IDs are included")
    }
    summary_df <- summary_df %>%
      dplyr::mutate(order = match(.data$series_id, row_order)) %>%
      dplyr::arrange(.data$order) %>%
      dplyr::select(-.data$order)
  }

  # Set highlight rows as numeric vector
  if (!is.null(highlight_rows)) {
    highlight_rows <- which(summary_df$series_id %in% highlight_rows)
  }

  # Add note about release date if earlier than rest of data
  date_notes <- df %>%
    dplyr::group_by(.data$series_id, .data$indicator) %>%
    dplyr::summarise(max_date = max(.data$date)) %>%
    dplyr::ungroup() %>%
    dplyr::mutate(indicator = dplyr::if_else(
      .data$max_date == max(.data$max_date),
      .data$indicator,
      paste0(.data$indicator, " (", format(.data$max_date, "%B %Y"), ")")
    )) %>%
    dplyr::select(.data$series_id, .data$indicator)

  summary_df <- summary_df %>%
    dplyr::ungroup() %>%
    dplyr::select(-.data$indicator) %>%
    dplyr::left_join(date_notes, by = "series_id") %>%
    dplyr::select(.data$indicator, dplyr::everything())

  summary_df <- summary_df %>%
    dplyr::rename(` ` = .data$indicator)

  names(summary_df) <- toupper(names(summary_df))

  # Define columns to include in output table
  cols_to_include <- names(summary_df)[names(summary_df) != "SERIES_ID"]

  # Drop "Change during govt" column if all values are NA
  # This occurs if all data series in the table commenced after Nov 2014
  if (all(is.na(summary_df$`SINCE NOV 2014`))) {
    cols_to_include <- cols_to_include[cols_to_include != "SINCE NOV 2014"]
  }

  # Create a basic flextable using the supplied dataframe
  flex <- summary_df %>%
    flextable::flextable(col_keys = cols_to_include)

  if (destination == "dashboard") {
    # Define cell colours ----
    # Create a summary table that will be used for conditional formatting
    # Note we do not use the dashboard-level ts_summ for this, as we want to ensure
    # any data pre-processing (such as rolling averages) are captured

    df_summ_data <- data %>%
      dplyr::mutate(indicator = dplyr::if_else(grepl(
        "jobactive",
        .data$series_id
      ),
      "Jobactive caseload",
      .data$indicator
      ))

    df_summ <- djprshiny::ts_summarise(df_summ_data) %>%
      dplyr::mutate(up_is_good = dplyr::if_else(grepl(
        "jobactive",
        .data$series_id
      ),
      FALSE,
      .data$up_is_good
      ))

    # Full palette for table
    full_pal <- grDevices::colorRampPalette(c("#E95A6A", "white", "#62BB46"))(100)

    # Function that takes a series ID and summary item and returns a colour
    get_col <- function(series_ids, item, df_summ = df_summ, full_pal = full_pal) {
      up_is_good <- get_summ(series_ids, "up_is_good", df = df_summ)
      x <- get_summ(series_ids, item, df = df_summ)
      x <- ifelse(up_is_good, x, 1 - x)
      x <- ceiling(x * 100)
      out <- full_pal[x]
      # If a colour cannot be found, return white
      if (length(out) != length(series_ids)) {
        out <- rep("white", length(series_ids))
      }
      out
    }

    # Add conditional formatting to flextable
    flex <- flex %>%
      # Latest value column
      flextable::bg(
        j = 3,
        source = "SERIES_ID",
        bg = function(x) {
          get_col(x,
            item = "ptile_latest_value",
            df_summ = df_summ,
            full_pal = full_pal
          )
        },
        part = "body"
      ) %>%
      # Change in past month column
      flextable::bg(
        j = 4,
        source = "SERIES_ID",
        bg = function(x) {
          get_col(x,
            item = "ptile_d_period_abs",
            df_summ = df_summ,
            full_pal = full_pal
          )
        },
        part = "body"
      ) %>%
      # # Change in past year column
      flextable::bg(
        j = 5,
        source = "SERIES_ID",
        bg = function(x) {
          get_col(x,
            item = "ptile_d_year_abs",
            df_summ = df_summ,
            full_pal = full_pal
          )
        },
        part = "body"
      )
  }
  # Set lineheight -----
  flex <- flex %>%
    flextable::line_spacing(space = 1)

  # Add sparklines
  if (destination == "dashboard") {
    spark_height <- 0.36
  } else {
    spark_height <- 0.26
  }

  flex <- flex %>%
    flextable::compose(
      j = 2,
      value = flextable::as_paragraph(
        flextable::gg_chunk(
          value = .,
          height = spark_height,
          width = 1
        )
      ),
      use_dot = TRUE
    )

  # Ensure the flextable fits the container (eg. Word doc) it is placed in
  flex <- flex %>%
    flextable::autofit(add_w = 0, add_h = 0, part = "all")

  # Centre content
  flex <- flex %>%
    flextable::align(
      j = 3:flextable::ncol_keys(flex),
      i = 1,
      align = "justify"
    ) %>%
    flextable::valign()

  # Add an extra header row
  header_row <- c(
    "",
    "Recent trend",
    "Current figures",
    "Change in latest period",
    "Change in past year",
    "Change since COVID"
  )

  if ("SINCE NOV 2014" %in% cols_to_include) {
    header_row <- c(header_row, "Change during govt")
  }

  flex <- flex %>%
    flextable::add_header_row(values = header_row)

  # Add borders
  flex <- flex %>%
    flextable::border_remove()

  if (destination == "dashboard") {
    flex <- flex %>%
      flextable::border(border.top = flextable::fp_border_default(
        color = "grey90", width = 0.25
      ))
  }

  flex <- flex %>%
    flextable::border(
      i = 1,
      border.top = flextable::fp_border_default()
    ) %>%
    flextable::border(i = nrow(summary_df), border.bottom = flextable::fp_border_default())

  # Ensure font, font size, and bolding is correct
  if (destination == "dashboard") {
    font_family <- "Roboto"
    font_size_main <- 10.5
    font_size_secondary <- 9
  } else if (destination == "briefing") {
    font_family <- "Arial"
    font_size_main <- 9
    font_size_secondary <- 8
  }

  flex <- flex %>%
    flextable::font(fontname = font_family) %>%
    flextable::font(fontname = font_family, part = "header") %>%
    flextable::fontsize(size = font_size_main) %>%
    flextable::fontsize(size = font_size_main, i = 1, part = "header") %>%
    flextable::fontsize(size = font_size_secondary, i = 2, part = "header") %>%
    flextable::bold(i = 1, part = "header")

  # Right align columns other than the first one (row label/indicator)
  flex <- flex %>%
    flextable::align(j = -1, align = "right") %>%
    flextable::align(j = -1, align = "right", part = "header")

  # Bold highlight rows, indent non-highlight rows
  if (!is.null(highlight_rows)) {
    flex <- flex %>%
      flextable::bold(i = highlight_rows, j = 1)

    all_rows <- seq_len(nrow(summary_df))
    non_highlight_rows <- all_rows[!all_rows %in% highlight_rows]

    flex <- flex %>%
      flextable::padding(i = non_highlight_rows, j = 1, padding.left = 20)

    flex <- flex %>%
      flextable::border(
        i = highlight_rows,
        border.top = flextable::fp_border_default()
      )
  }

  # Add caption / footer
  if (destination == "dashboard") {
    caption_notes <- paste0(
      notes,
      " Differences are calculated based on unrounded numbers, following the ABS convention. Shading of cells is based on how the indicator relates to historical trends."
    )
  } else {
    if (is.null(notes)) {
      caption_notes <- NULL
    } else {
      caption_notes <- notes
    }
  }

  table_caption <- caption_auto(df,
    notes = caption_notes
  )

  # Add footer caption
  flex <- flex %>%
    flextable::add_footer(` ` = table_caption) %>%
    flextable::merge_at(
      j = 1:flextable::ncol_keys(flex),
      part = "footer"
    ) %>%
    flextable::italic(part = "footer") %>%
    flextable::font(fontname = font_family) %>%
    flextable::fontsize(
      size = font_size_secondary * 0.85,
      part = "footer"
    ) %>%
    flextable::color(
      part = "footer",
      color = "#343a40"
    ) %>%
    flextable::line_spacing(
      part = "footer",
      space = 0.8
    ) %>%
    flextable::font(
      fontname = font_family,
      part = "footer"
    ) %>%
    flextable::italic(part = "footer")

  # Add title to briefing tables and resize columns
  if (destination == "briefing") {
    flex <- flex %>%
      flextable::set_caption(caption = title)

    flex <- flex %>%
      flextable::width(
        j = c(3:flextable::ncol_keys(flex)),
        width = 0.88
      ) %>%
      flextable::width(
        j = 1,
        width = 2
      )
  }

  flex
}
