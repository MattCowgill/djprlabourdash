labour_ui <- function(...) {
  djprshiny::djpr_page(
    title = shiny::HTML("DJPR Jobs<br>Dashboard"),
    page_overview(),
    page_indicators(),
    navbarMenu(
      "Groups",
      page_sex(),
      page_age(),
      page_ltunemp(),
      page_aboriginal(),
      page_disability(),
      page_migration()
    ),
    navbarMenu(
      "Regions",
      page_vicregions(),
      page_ausregions()
    ),
    page_industries()
  )
}
