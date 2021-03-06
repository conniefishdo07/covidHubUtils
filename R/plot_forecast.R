#' Plot forecasts and optional truth for only one selected target variable.
#' Faceted plots for multiple models, locations and forecast dates are 
#' supported with specified facet formula. 
#' 
#' @param forecast_data data frame with truth and forecasts from load_forecasts()
#' @param truth_data optional data frame with forecasts in the format returned 
#' by load_truth().
#' @param models vector of strings specifying models to plot. 
#' Default to all models in forecast_data.
#' @param target_variable string specifying target type. It should be one of 
#' "cum death", "inc case", "inc death"
#' @param locations string for fips code or 'US'. 
#' Default to all locations in forecast_data.
#' @param facet interpretable facet option for ggplot
#' @param facet_scales argument for scales in ggplot2::facet_wrap. Default to "fixed".
#' @param forecast_dates date string vectors for forecast dates to plot. 
#' Default to forecast_dates present in the data.
#' @param intervals values indicating which central prediction interval levels 
#' to plot. NULL means only plotting point forecasts.
#' If not provided, it will default to c(.5, .8, .95).
#' @param horizon forecasts are plotted for the horizon time steps after the 
#' forecast date. Default to all available horizons in forecast data. 
#' @param truth_source character specifying where the truth data will
#' be loaded from if truth_data is not provided. 
#' Otherwise, this character specifies the data source to plot. 
#' Currently support "JHU","USAFacts" and "NYTimes".
#' @param plot_truth boolean for showing truth data in plot. Default to FALSE.
#' @param plot boolean for showing the plot. Default to TRUE.
#' Currently supports "JHU","USAFacts", "NYTimes". Default to "JHU".
#' @param fill_by_model boolean for specifying colors in plot.
#' If TRUE, separate colors will be used for each model.
#' If FALSE, only blues will be used for all models. Default to FALSE. 
#' @param truth_as_of the plot includes the truth data that would have been 
#' in real time as of the truth_as_of date (not using this parameter when truth data 
#' is from github repo)
#' @param title optional text for the title of the plot. If left as "default",
#' the title will be automatically generated. If "none", no title will be plotted. 
#' @param subtitle optional text for the subtitle of the plot. If left as "default",
#' the subtitle will be automatically generated. If "none", no subtitle will be plotted. 
#' @param show_caption logical, if TRUE, caption will be included showing data sources

#' 
#' @return invisible ggplot object
#' 
#' @export
plot_forecast <- function(forecast_data,
                          truth_data = NULL, 
                          models,
                          target_variable,
                          locations,
                          facet = NULL,
                          facet_scales = "fixed",
                          forecast_dates,
                          intervals,
                          horizon,
                          truth_source = "JHU",
                          plot_truth = TRUE,
                          plot = TRUE,
                          fill_by_model = FALSE,
                          truth_as_of = NULL, 
                          title = "default", 
                          subtitle = "default",
                          show_caption = TRUE){
 
  # title format
  if(is.na(title))
    stop("Error in plot_forecast: title argument interpretable as a character.")
  
  # subtitle format
  if(is.na(subtitle))
    stop("Error in plot_forecast: subtitle argument interpretable as a character.")
  
  # optional models parameter. Default to all models in forecast_data
  if (!missing(models)){
    if (!all(models %in% forecast_data$model)) {
      stop("Error in plot_forecast: Not all models are available in forecast data.")
    }
  } else {
    models <- unique(forecast_data$model)
  }
  
  # optional locations parameter. Default to all locations in forecast_data
  if (missing(locations)){
    locations <- unique(forecast_data$location)
  }
  
  # validate location fips code
  all_valid_fips <- covidHubUtils::hub_locations$fips
  
  locations <- match.arg(locations, 
                        choices = all_valid_fips, 
                        several.ok = TRUE)
  
  if (!all(locations %in% forecast_data$location)){
    stop("Error in plot_forecast: Not all locations are available in forecast_data.")
  }
  
  
  # validate truth_source
  truth_source <- match.arg(truth_source, 
                            choices = c("JHU","USAFacts", "NYTimes"), 
                            several.ok = FALSE)
  
  # validate target_variable
  target_variable <- match.arg(target_variable, 
                               choices = c("cum death",
                                           "inc case",
                                           "inc death"), 
                               several.ok = FALSE)
  
  if (!(target_variable %in% forecast_data$target_variable)){
    stop("Error in plot_forecast: Please provide a valid target variable.")
  }
  
  
  # validate truth data if provided
  if (!is.null(truth_data)){
    # check if truth_data has all needed columns
    columns_check <- all(c("model", "target_variable", 
                          "target_end_date", "location","value") 
                        %in% colnames(truth_data))
    if(!columns_check){
      stop("Error in plot_forecast: Please provide columns model, 
           target_variable, target_end_date, location and value in truth_data.")
    } else {
      # check if truth_data has data from specified source
      if (!(paste0("Observed Data (",truth_source,")") %in% truth_data$model)) {
        stop("Error in plot_forecast: Please provide a valid truth_source to plot.")
      }
      # check if truth_data has data from specified location
      if (!all(locations %in% truth_data$location)){
        stop("Error in plot_forecast: Please provide a valid location to plot.")
      }
      # check if truth_data has specified target variable
      if (!(target_variable %in% truth_data$target_variable)){
        stop("Error in plot_forecast: Please provide a valid target variable.")
      }
    }
  }
  
  
  # validate forecast_dates
  
  if (missing(forecast_dates)){
    forecast_dates <- unique(forecast_data$forecast_date)
  } else {
    forecast_dates <- as.Date(forecast_dates)
    if (!all(forecast_dates %in% forecast_data$forecast_date)){
      stop ("Error in plot_forecast: Not all forecast_dates are available in forecast data.")
    }
  }
  
  
  # if interval is missing, default to a reduced set of intervals available in forecast data
  if (missing(intervals)){
    lower_bounds <- unique(forecast_data[forecast_data$type == 'quantile' &
                                           forecast_data$quantile < 0.5,]$quantile)
    
    # if quantile forecasts are not available, plot point forecasts only
    if ('NA' %in% lower_bounds){
      intervals = NULL
    } else {
      # only plot .95 interval if more than 5 models are selected
      if (length(unique(models)) > 5){
        intervals <- c(.95)
      } else {
        # generate intervals from lower bounds
        intervals <- lapply(lower_bounds, function(l){
          1-as.numeric(2*l)
        })
        
        # for readability
        if (all(c(.5, .8, .95) %in% intervals)){
          intervals <- c(.5, .8, .95)
        }
      }
    }
  }
  
  if (!is.null(intervals) & length(unique(models)) > 5){
    intervals <- c(.95)
  }
  
  # generate quantiles based on given intervals
  quantiles_to_plot <- unlist(lapply(intervals, function(interval){
    c(0.5 - as.numeric(interval)/2,
     0.5 + as.numeric(interval)/2)
  }))
  
  
  # set colors
  if (fill_by_model){
    if (length(unique(models)) <= 5){
      color_families <- c("Blues", "Oranges", "Greens", "Purples", "Reds")
      colourCount <- length(quantiles_to_plot)/2+1
      model_colors <- purrr::map(
        color_families[1:length(unique(models))],
        function(color_family){
          getPalette = colorRampPalette(RColorBrewer::brewer.pal(4, color_family))
          getPalette(colourCount)
          }
        )
      
      ribbon_colors <- RColorBrewer::brewer.pal(4, "Greys")[1:3]
      forecast_colors <- unlist(lapply(model_colors, tail, n = 1))
      interval_colors <- unlist(lapply(model_colors, head, n = colourCount-1))
    } else {
      # interpolate color pallets to more than 5 colors
      colourCount <- length(quantiles_to_plot)/2
      modelCount <- length(unique(models))
      # use 8 instead of 9 to avoid black and grey shades
      getPalette = colorRampPalette(RColorBrewer::brewer.pal(8, "Set1"))
      model_colors <- getPalette(modelCount)
      
      ribbon_colors <- RColorBrewer::brewer.pal(4, "Greys")[1:3]
      forecast_colors <- unlist(lapply(model_colors, tail, n = 1))
      # create 95% PI color
      interval_colors <- unlist(lapply(model_colors, function(color){
        colorspace::adjust_transparency(color, 0.3)}
        ))
    }
  } else {
    # only use blue
    colourCount = max(length(quantiles_to_plot)/2+1, 2)
    getPalette = colorRampPalette(RColorBrewer::brewer.pal(4, "Blues"))
    blues = getPalette(colourCount)
    forecast_colors <- rep(tail(blues,1), length(unique(models)))
    interval_colors <- rep(blues[1:(length(blues)-1)],
                           length(unique(models)))
    ribbon_colors <- blues[1:(length(blues)-1)]
  }
  
  if (!is.null(truth_as_of)){
    warning("Warning in plot_forecast: truth_as_of is not used to load versioned truth data.
            Will be available soon.")
  }
  
  # include truth from remote git hub repo by default
  # not using truth_as_of if we are loading truth from git hub repos
  plot_data = get_plot_forecast_data (forecast_data = forecast_data, 
                                      truth_data = truth_data,
                                      models_to_plot = models,
                                      forecast_dates_to_plot = as.Date(forecast_dates),
                                      horizons_to_plot = horizon,
                                      quantiles_to_plot = quantiles_to_plot,
                                      locations_to_plot = locations,
                                      plot_truth = plot_truth,
                                      truth_source = truth_source,
                                      target_variable_to_plot = target_variable)
 

  # generate caption and full target variable
  if(show_caption){
    if(!is.null(truth_as_of)){
      caption <- paste0("source: ", truth_source," (observed data as of ",
                        as.Date(truth_as_of), "), ", 
                        paste(models, collapse = ', '), " (forecasts)")
      
      caption <- paste(strwrap(caption, dev.size("px")[1]), collapse="\n")
    } else {
      caption <- paste0("source: ", truth_source," (observed data), ",
                        paste(models, collapse = ', ')," (forecasts)")
      
      caption <- paste(strwrap(caption, dev.size("px")[1]), collapse="\n")
    }
  } else {
    caption <- NULL
  }
  
  if (target_variable == "cum death"){
    full_target_variable = "Cumulative Deaths"
  } else if (target_variable == "inc case"){
    full_target_variable = "Incident Cases"
  } else if (target_variable == "inc death"){
    full_target_variable = "Incident Deaths"
  } else if (target_variable == "inc hosp"){
    full_target_variable = "Incident Hospitalizations"
  }
  
  # split plot data
  plot_data_forecast <- plot_data %>%
    dplyr::filter(truth_forecast == "forecast")
  
  plot_data_truth <- plot_data %>%
    dplyr::filter(!is.na(point),truth_forecast == "truth") %>%
    dplyr::rename(truth_model = model) %>%
    dplyr::select(-forecast_date)
  
  # generate title if specified as "default", otherwise leave as is
  if(title == "default") {
    title <- paste0("Weekly COVID-19 ", full_target_variable, 
                    ": observed and forecasted")
  }
  
  if(title == "none") {
    title <- NULL
  }
  
  # generate subtitle if specified as "default", otherwise leave as is
  if (subtitle == "default"){
    subtitle <- paste0("Selected location(s): ", 
                      paste(unique(plot_data_forecast$location), collapse = ', '),
                      "\nSelected forecast date(s): ",
                      paste(unique(plot_data_forecast$forecast_date), collapse = ', ')
                      )
  }
  
  if (subtitle == "none"){
    subtitle <- NULL
  }
  
  

  # generate plot
  graph <- ggplot2::ggplot(data = plot_data_forecast, ggplot2::aes(x= target_end_date))
  
  # plot selected prediction intervals
  if (!is.null(intervals)){
    graph <- graph  +
      ggplot2::geom_ribbon(data = plot_data_forecast %>%
                  dplyr::filter(type == "quantile"),
                mapping = ggplot2::aes(ymin=lower, 
                                       ymax=upper,
                                       group = interaction(`Prediction Interval`, model, 
                                                           location, forecast_date),
                                       fill = interaction(`Prediction Interval`, model)),
                show.legend=FALSE) +
      ggplot2::scale_fill_manual(name = "Prediction Interval", 
                                 values = interval_colors) +
      # create a transparent layer with grey colors to get prediction interval legend
      ggnewscale::new_scale_fill() +
      ggplot2::geom_ribbon(data = plot_data_forecast %>%
                             dplyr::filter(type == "quantile"),
                           mapping = ggplot2::aes(ymin=lower, 
                                                  ymax=upper, 
                                                  fill = `Prediction Interval`), 
                           alpha=0) +
      ggplot2::scale_fill_manual(name = "Prediction Interval", 
                                 values = ribbon_colors) +
      # reset alpha in legend fill
      ggplot2::guides(
        fill = ggplot2::guide_legend(override.aes = list(alpha = 1)))
  }
  
  # plot point forecasts and truth 
  graph <- graph +
    #forecast
    ggplot2::geom_line(data = plot_data_forecast %>%
                dplyr::filter(!is.na(point)),
              mapping = ggplot2::aes(x = target_end_date, 
                                     y = point, 
                                     group = interaction(model, location, forecast_date),
                                     color = model)) +
    ggplot2::geom_point(data = plot_data_forecast %>%
                 dplyr::filter(!is.na(point)),
               mapping = ggplot2::aes(x = target_end_date, 
                                      y = point, 
                                      color = model)) +
    ggplot2::scale_color_manual(name = "Model", 
                                values = forecast_colors) +
    #truth
    ggnewscale::new_scale_color() +
    ggplot2::geom_line(data = plot_data_truth %>%
                         dplyr::filter(!is.na(point)),
                       mapping = ggplot2::aes(x = target_end_date, 
                                              y = point, 
                                              color = truth_model)) +
    ggplot2::geom_point(data = plot_data_truth %>%
                          dplyr::filter(!is.na(point)),
                        mapping = ggplot2::aes(x = target_end_date, 
                                               y = point, 
                                               color = truth_model)) +
    ggplot2::scale_color_manual(name = "Truth", values = "black")
  
  # add facets
  if(!is.null(facet)){
    graph <- graph + 
      ggplot2::facet_wrap(facets = facet, scales = facet_scales, 
                          labeller = ggplot2::label_wrap_gen(multi_line=FALSE))
  
  }
  
  # add labels, title, subtitle and caption
  graph <- graph + 
    ggplot2::scale_x_date(name = NULL, date_breaks="1 month", date_labels = "%b %d") +
    ggplot2::ylab(full_target_variable) +
    ggplot2::labs(title = title,
                  subtitle = subtitle,
                  caption = caption)
  
  if (plot){
    print(graph)
  }
  
  return (invisible(graph))
}
