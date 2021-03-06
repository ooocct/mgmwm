# Copyright (C) 2014 - 2018  Gaetan Bakalli, Stephane Guerrier.
#
# This file is part of classimu R Methods Package
#
# The `mgmwm` R package is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# The `mgmwm` R package is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

#' Multivariate Generalized Method of Wavelet Moments (MGMWM) for IMUs
#'
#'
#' Performs estimation of time series models by using the GMWM estimator.
#' @param mimu                  A \code{mimu} object.
#' @param model                 A \code{ts.model} object containing one of the allowed models.
#' @param CI                    A \code{bolean} to compute the confidence intervals for estimated parameters.
#' @param alpha_ci              A \code{double} between 0 and 1 that correspondings to the
#'                              \eqn{\frac{\alpha}{2}}{alpha/2} value for the parameter
#'                              confidence intervals.
#' @param n_boot_ci_max         A \code{double} representing the maximum number of bootstrap replicates
#'                              for parameters confidence intervals computaion.
#' @param stationarity_test     A \code{bolean} to compute the near-stationarity test.
#' @param B_stationarity_test   A \code{double} representing the number of bootstrap replicates.
#'                              for near-stationarity test computation.
#' @param alpha_near_test       A \code{double} between 0 and 1 that correspondings to the
#'                              rejection region for the p value in the near-stationarity test
#' @param seed                  An \code{integer} that controls the reproducibility of the
#'                              auto model selection phase.
#'
#' @return A \code{mgmwm} object with the structure:
#' \describe{
#'  \item{estimates}{Estimated Parameters Values from the MGMWM Procedure}
#'  \item{wv_empir}{The data's empirical wavelet variance}
#'  \item{ci_low}{Lower Confidence Interval}
#'  \item{ci_high}{Upper Confidence Interval}
#'  \item{obj_fun}{Value of the objective function at Estimated Parameter Values}
#'  \item{theo}{Summed Theoretical Wavelet Variance}
#'  \item{decomp.theo}{Decomposed Theoretical Wavelet Variance by Process}
#'  \item{scales}{Scales of the GMWM Object}
#'  \item{model.type}{Models being guessed}
#'  \item{alpha}{Alpha level used to generate confidence intervals}
#'  \item{model}{\code{ts.model} supplied to gmwm}
#'  \item{model.hat}{A new value of \code{ts.model} object supplied to gmwm}
#' }
#' @details
#' This function is under work. Some of the features are active. Others... Not so much.
#'
#' The V matrix is calculated by:
#' \eqn{diag\left[ {{{\left( {Hi - Lo} \right)}^2}} \right]}{diag[(Hi-Lo)^2]}.
#'
#' The function is implemented in the following manner:
#' 1. Calculate MODWT of data with levels = floor(log2(data))
#' 2. Apply the brick.wall of the MODWT (e.g. remove boundary values)
#' 3. Compute the empirical wavelet variance (WV Empirical).
#' 4. Obtain the V matrix by squaring the difference of the WV Empirical's Chi-squared confidence interval (hi - lo)^2
#' 5. Optimize the values to obtain \eqn{\hat{\theta}}{theta^hat}
#' 6. If FAST = TRUE, return these results. Else, continue.
#'
#'Loop  k = 1 to K
#' Loop h = 1 to H
#' 7. Simulate xt under \eqn{F_{\hat{\theta}}}{F_theta^hat}
#' 8. Compute WV Empirical
#' END
#' 9. Calculate the covariance matrix
#' 10. Optimize the values to obtain \eqn{\hat{\theta}}{theta^hat}
#'END
#' 11. Return optimized values.
#'
#'
#' The function estimates a variety of time series models. If type = "imu" or "ssm", then
#' parameter vector should indicate the characters of the models that compose the latent or state-space model. The model
#' options are:
#' \describe{
#'   \item{"AR1"}{a first order autoregressive process with parameters \eqn{(\phi,\sigma^2)}{phi, sigma^2}}
#'   \item{"GM"}{a guass-markov process \eqn{(\beta,\sigma_{gm}^2)}{beta, sigma[gm]^2}}
#'   \item{"DR"}{a drift with parameter \eqn{\omega}{omega}}
#'   \item{"QN"}{a quantization noise process with parameter \eqn{Q}}
#'   \item{"RW"}{a random walk process with parameter \eqn{\sigma^2}{sigma^2}}
#'   \item{"WN"}{a white noise process with parameter \eqn{\sigma^2}{sigma^2}}
#' }
#' @import gmwm
#' @examples
#' # AR
#' set.seed(1336)
#' n = 200
#' data = gen_gts(n, AR1(phi = .99, sigma2 = 0.01) + WN(sigma2 = 1))
#'
#' # Models can contain specific parameters e.g.
#' adv.model = gmwm(AR1(phi = .99, sigma2 = 0.01) + WN(sigma2 = 0.01),
#'                             data)
#'
#' # Or we can guess the parameters:
#' guided.model = gmwm(AR1() + WN(), data)
#'
#' # Want to try different models?
#' guided.ar1 = gmwm(AR1(), data)
#'
#' # Faster:
#' guided.ar1.wn.prev = update(guided.ar1, AR1()+WN())
#'
#' # OR
#'
#' # Create new GMWM object.
#' # Note this is SLOWER since the Covariance Matrix is recalculated.
#' guided.ar1.wn.new = gmwm(AR1()+WN(), data)
#'
#' @export mgmwm
mgmwm = function(mimu, model = NULL, CI = FALSE, alpha_ci = NULL, n_boot_ci_max = NULL,
                 stationarity_test = FALSE, B_stationarity_test= 30, alpha_near_test = NULL,
                 seed = 2710){

  # Not estimate the model if provide an "mgmwm" of "cvwvic" object.
  if(is.mimu(mimu)){
    new_estimation = TRUE
    if (is.null(model)){
      stop("No available model with `mimu` object of class `mimu`.")
    }
  }else{
    if (is.null(model)){
      new_estimation = FALSE

      if(is.mgmwm(mimu) || is.cvwvic(mimu)){
        model_hat = mimu$model_hat
        mimu = mimu$mimu
      }else{
        stop("`mimu` must be created from a `mgmwm` or a `cvwvic` object since no model is provided. ")
      }

    }else{
      if(is.tsmodel(model)){
        if ((all(mimu$model_hat$desc == model$desc)) && (length(model$desc) == length(mimu$model_hat$desc))){
          new_estimation = FALSE
          model_hat = mimu$model_hat
        }else{
          new_estimation = TRUE
        }
      }else{
        stop("Incorrect inputs: `mimu` must be created from a `mimu`, `mgmwm` or a `cvwvic` object;
             `model` must be created from a `ts.model` object using a supported component (e.g. AR1(),
             ARMA(p,q), DR(), RW(), QN(), and WN().")
      }

      if(is.mgmwm(mimu) || is.cvwvic(mimu)){
        mimu = mimu$mimu
      }else if (!is.mimu(mimu)){
        stop("No `mimu` object provided.")
      }
    }
  }


  ##### case where mimu == mgmwm of cvwvic model is a specific model
  # a) mgmwm : warning we fit the new one
  # b) cvwvic: check if estimated previously. Y-> extract info N-> estrimate the model

  # Check if mimu is a valid object
  if(!is.mimu(mimu)){
    stop("No available `mimu` object. ")
  }

  # Set default value for alpha of confidence intervals.
  if(is.null(alpha_ci)){
    alpha_ci = .05
  }else{
    alpha_ci = alpha_ci
  }

  # Set default value for p value threshold of near-stationarity test.
  if(is.null(alpha_near_test)){
    alpha_near_test = .05
  }else{
    alpha_near_test = alpha_near_test
  }

  # Set default value for bootstrap replicates of near-stationarity test
  if(is.null(B_stationarity_test)){
    B_stationarity_test = 100
  }else{
    B_stationarity_test = B_stationarity_test
  }


  if(is.null(n_boot_ci_max)){
    n_boot_ci_max = 300
  }else{
    n_boot_ci_max = n_boot_ci_max
  }

  # Number of differentn time series in mimu object
  n_replicates = length(mimu)

  # Extract tau max
  length_tau = rep(NA,n_replicates)

  for (i in 1:n_replicates){
    length_tau[i] = length(mimu[[i]]$tau)
  }

  # Vector of maximum tau and scales
  tau_max_vec = mimu[[which.max(length_tau)]]$tau
  scales_max_vec = mimu[[which.max(length_tau)]]$scales

  # Set seed for reproducibility
  set.seed(seed)


  N = rep(NA,n_replicates)

  if(new_estimation == TRUE){

    # Extract the type of model
    desc = model$desc

    # Number of latent pocesses in model
    n_process = length(model$desc)

    # Number of parameters in model
    np = model$plength

    # Name of parameters in model
    obj_desc = model$obj.desc

    # Value of parameters in model
    theta = model$theta

    ## Compute the starting value with univariate gmwm on every error signal
    N = rep(NA,n_replicates)
    param_starting = matrix(NA,n_replicates,np)

    for (i in 1:n_replicates){
      # Length of each error signal
      N[i] = length(mimu[[i]]$data)

      # Extract the data from mimu object
      data = mimu[[i]]$data

      # Set the number of boostrap replicates to compute covariance matrix
      if(N[i] > 10000){
        G = 1e6
      }else{
        G = 20000
      }

      # Compute the parameter value from gmwm
      uni_gmwm = gmwm::gmwm(model, data, model.type = 'imu')[[1]]

      # Store the univariate gmwm
      param_starting[i,] = uni_gmwm
    }

    ## Select as starting value that minimize the mgmwm objective function.
    obj_value_starting_value = rep(NA, n_replicates)
    mgmwm_list = list()
    for (i in 1:n_replicates){
      starting_value = inv_param_transform(model, param_starting[i,])
      mgmwm_list[[i]] = optim(starting_value, mgmwm_obj_function, model = model, mimu = mimu)
      obj_value_starting_value[i] = mgmwm_list[[i]]$value
    }

    # Compute the parameter value and the objective function
    out = mgmwm_list[[which.min(obj_value_starting_value)]]


    # Create estimated model object
    model_hat = model
    class(model_hat) = "ts.model"

    # Pass on the estimated paramters onto the model.
    model_hat$starting = FALSE
    model_hat$theta = out$par

    # Pass obj_value to the model
    model_hat$obj_value = out$value

    # Transform the parameter
    model_hat$theta = param_transform(model_hat,model_hat$theta)


    # WV implied by the parameter
    model_hat$wv_implied = wv_theo(model_hat, tau_max_vec)

    # Extact individual model for theoretical decomposition
    model_hat$desc_decomp_theo = desc_decomp_theo_fun(model_hat, n_process)

    # Compute individual theoretical wv
    decomp_theo = list()
    for (i in 1:n_process){
      decomp_theo[[i]] =  wv_theo(model_hat$desc_decomp_theo[[i]], tau_max_vec)
    }

    model_hat$decomp_theo = decomp_theo

  }else{
    # Number of latent pocesses in model
    n_process = length(model_hat$desc)

    # Number of parameters in model
    np = model_hat$plength
  }
  # Perform the near-stationarity test
  if(stationarity_test == TRUE){

    p_value = near_stationarity_test(mimu = mimu, model_hat = model_hat , model = model,
                                     seed = seed, B_stationarity_test = B_stationarity_test)
    # decision rule from the test
    if(p_value >= alpha_near_test){
      test_res = "Data are stationary"
    }else{
      test_res = "Data are nearly-stationary"
    }
  }else{
    test_res = "Near-stationarity test not computed. Set `stationarity_test = TRUE`"
    p_value = NA
  }

  # Compute the CI for paramters
  if(CI == TRUE){
    distrib_param = ci_mgmwm(model_ci = model_hat, mimu = mimu,
                  n_boot_ci_max = n_boot_ci_max, n_replicates, seed = seed)

    ci_low = rep(NA,np)
    ci_high = rep(NA,np)
    #Compute the empirical quantile
    for (k in 1:np){
      ci_low[k] = as.numeric(quantile(distrib_param[,k],(alpha_ci/2)))
      ci_high[k] = as.numeric(quantile(distrib_param[,k],(1-alpha_ci/2)))
    }
  }else{
    distrib_param = "Confidence intervals not computed. Set `CI = TRUE`"
    ci_low = NA
    ci_high = NA
  }


  estimates = as.matrix(model_hat$theta)
  rownames(estimates) = model_hat$process.desc
  colnames(estimates) = "Estimates"

  obj_value = model_hat$obj_value
  names(obj_value) = "Value Objective Function"

  options(warn=-1)

  # Cancel previous seed
  set.seed(as.numeric(format(Sys.time(),"%s"))/10)
  options(warn=0)


  out = structure(list(estimates = estimates,
                       obj_value = obj_value,
                       model_hat = model_hat,
                       scales_max_vec = scales_max_vec,
                       p_value = p_value,
                       test_result = test_res,
                       distrib_param = distrib_param,
                       ci_low = ci_low,
                       ci_high = ci_high,
                       mimu = mimu), class = "mgmwm")
  invisible(out)
}


#' @export plot.mgmwm
plot.mgmwm = function(obj_list, decomp = FALSE,
                      add_legend_mgwmw = TRUE, legend_pos = NULL, ylab_mgmwm = NULL){

  # mimu_obj_name = attr(obj_list[[7]], "exp.name")
  # mimu_obj_name = paste("Empirical WV", mimu_obj_name)

  if (is.null(ylab_mgmwm)){
    ylab = expression(paste("Wavelet Variance ", nu^2, sep = ""))
  }else{
    ylab = ylab_mgmwm
  }


  plot(obj_list$mimu, add_legend = FALSE,ylab = ylab)
  U = length(obj_list$model_hat$decomp_theo)
  col_wv = hcl(h = seq(100, 375, length = U + 1), l = 65, c = 200, alpha = 1)[1:U]

  if(decomp == TRUE){
    # Number of Latent proces

    # Plot lines of decomp theo
    for (i in 1:U){
      lines(t(obj_list$scales_max_vec), obj_list$model_hat$decomp_theo[[i]], col = col_wv[i])
    }
  }
  # Plot implied WV
  lines(t(obj_list$scales_max_vec),obj_list$model_hat$wv_implied, type = "l", lwd = 3, col = "#F47F24", pch = 1, cex = 1.5)
  lines(t(obj_list$scales_max_vec),obj_list$model_hat$wv_implied, type = "p", lwd = 2, col = "#F47F24", pch = 1, cex = 1.5)

  if(decomp == TRUE){
    legend_names = c("Implied WV", obj_list$model_hat$desc)
    col_legend = c("#F47F24",col_wv)
    p_cex_legend = c(1.5,rep(NA,U))
  }else{
    legend_names = c("Implied WV")
    col_legend = c("#F47F24")
    p_cex_legend = c(1.5)
  }

  if (is.null(legend_pos)){
    legend_pos = "bottomleft"
  }
  if (add_legend_mgwmw == TRUE){
    legend(legend_pos, legend_names, bty = "n", lwd = 1, pt.cex = 1.5, pch = p_cex_legend, col = col_legend)
  }
}


near_stationarity_test = function(mimu = mimu, model_ns = model,model_hat = model_hat,
                                  seed = seed, B_stationarity_test = B_stationarity_test){

  n_replicates = length(mimu)

  starting_value = inv_param_transform(model_ns,model_hat$theta)

  distrib_H0 = rep(NA,B_stationarity_test)

  for (i in 1:B_stationarity_test){
    sim.H0 = list()
    for (j in 1:n_replicates){
      set.seed(i*j+seed+1000)
      sim.H0[[j]] = simts::gen_gts(mimu[[j]]$N, model_hat)
    }
    simu.obj = make_mimu(for_test = sim.H0, freq = attr(mimu,"freq"), unit = "s", sensor.name = "",
                                  exp.name = "")
    distrib_H0[i] = optim(starting_value, mgmwm_obj_function, model = model_ns, mimu = simu.obj)$value
  }

  # extract p_value from the test
  p_value = sum(distrib_H0 >= model_hat$obj_value)/B_stationarity_test
}

#' @import iterpc
ci_mgmwm = function(model_ci = model_ci, mimu = mimu,
                    n_boot_ci_max = n_boot_ci_max, n_replicates = n_replicates,
                    seed = seed){

  np = model_ci$plength

  # Set up starting value in model to false
  model_ci$starting = TRUE

  I = iterpc::iterpc(n_replicates, n_replicates, replace = TRUE)
  perm = iterpc::getall(I)
  n_permutation = dim(perm)[1]


  starting_value = inv_param_transform(model_ci, model_ci$theta)

  model_ci$starting = TRUE

  if(n_permutation < n_boot_ci_max){
    distrib_param = matrix(NA,n_permutation,np)
    for (i in 1:n_permutation){
      sampled_imu_obj = list()
      for (j in 1:n_replicates){
        sampled_imu_obj[[j]] = mimu[[perm[i,j]]]
        class(sampled_imu_obj) = "mimu"
      }
      distrib_param[i,] = optim(starting_value, mgmwm_obj_function, model = model_ci, mimu = sampled_imu_obj)$par
      distrib_param[i,] = param_transform(model_ci, distrib_param[i,])
    }
  }else{
    n_permutation = n_boot_ci_max
    distrib_param = matrix(NA,n_permutation,np)
    for (i in 1:n_permutation){
      # Seed for reproducibility
      set.seed(i+seed)

      sampled_imu_obj = list()
      sampled_permutation = sample(1:n_replicates, n_replicates, replace = TRUE)
      for (j in 1:n_replicates){
        sampled_imu_obj[[j]] = mimu[[sampled_permutation[j]]]
        class(sampled_imu_obj) = "mimu"
      }
      distrib_param[i,] = optim(starting_value, mgmwm_obj_function, model = model_ci, mimu = sampled_imu_obj)$par

      distrib_param[i,] = param_transform(model_ci, distrib_param[i,])
    }
  }
  distrib_param
}

#' @export
desc_decomp_theo_fun = function(model_hat, n_process){

  out_desc = list()

  # Initialise counter
  counter = 1

  for (i in 1:n_process){

    if (model_hat$desc[i] == "RW"){
      out_desc[[i]] = RW(gamma2 = model_hat$theta[counter])
      counter = counter + 1
    }

    # is white noise?
    if (model_hat$desc[i] == "WN"){
      out_desc[[i]] =WN(sigma2 = model_hat$theta[counter])
      counter = counter + 1
    }

    # is drift?
    if (model_hat$desc[i] == "DR"){
      out_desc[[i]] = DR(omega = model_hat$theta[counter])
      counter = counter + 1
    }

    # is quantization noise?
    if (model_hat$desc[i] == "QN"){
      out_desc[[i]] = QN(q2 = model_hat$theta[counter])
      counter = counter + 1
    }

    # is AR1?
    if (model_hat$desc[i] == "AR1"){
      out_desc[[i]] = AR1(phi = model_hat$theta[counter], sigma2 = model_hat$theta[counter + 1])
      counter = counter + 2
    }
  }
  out_desc
}

#'@export summary.mgmwm
summary.mgmwm = function(object){

  out = object$estimates


  if(is.na(object$ci_low[1])){
    print("Confidence intervals not computed")
  }else{
    out.coln = colnames(out)
    out = cbind(out, object$ci_low, object$ci_high )
    colnames(out) = c(out.coln, "CI Low", "CI High")
  }



  x = structure(list(estimates=out,
                     obj_value= object$obj_value,
                     near_stationarity_test = object$test_res,
                     p_value_nr_test = object$p_value))
  x
}

#' @export
param_name = function(model){

  x = list()

  counter = 1

  for (j in 1:length(model$process.desc)){

    # is quantization noise?
    if (model$process.desc[j] == "QN"){
      x[[counter]] = expression(paste(hat(Q)^2))
      counter = counter + 1
    }

    # is white noise?
    if (model$process.desc[j] == "WN"){
      x[[counter]] =  expression(paste(hat(sigma)^2))
      counter = counter + 1
    }

    # is AR1?
    if (model$process.desc[j] == "AR1"){

      x[[counter]] = expression(paste(hat(phi)))

      counter = counter + 1

    }

    # is random walk?
    if (model$process.desc[j] == "RW"){
      x[[counter]] = expression(paste(hat(gamma)^2))
      counter = counter + 1
    }

    # is random walk?
    if (model$process.desc[j] == "SIGMA2"){
      x[[counter]] =  expression(paste(hat(nu)^2))
      counter = counter + 1
    }

    # is drift?
    if (model$process.desc[j] == "DR"){
      x[[counter]] = expression(paste(hat(omega)^2))
      counter = counter + 1
    }

  }
  x
}



#' @export plot_CI
plot_CI = function(obj_list, units = NULL, xlab = NULL, ylab = NULL,
                   col_dens = NULL, col_ci = NULL, nb_ticks_x = NULL,
                   nb_ticks_y = NULL, ci_wv = NULL, point_cex = NULL,
                   point_pch = NULL,col_line = NULL, ...){

  n_param = length(obj_list$model_hat$process.desc)

  if(n_param <= 3){
    par(mfrow=c(1,n_param), mar = c(3,3,3,2))
  }else{
    q  = ceiling(n_param/2)
    par(mfrow=c(2,q), mar = c(3,3,3,2))
  }

  for (i in 1:n_param){

    density_param = (density(obj_list$distrib_param[,i]))



    # Labels
    if (is.null(xlab)){
      xlab = obj_list$model_hat$process.desc[i]
    }else{
      xlab = xlab
    }
    ### to do
    if (is.null(ylab)){
      ylab = "Smoothed Density"
    }else{
      ylab = ylab
    }

    param_name_i = param_name(model = obj_list$model_hat)


    main = param_name_i[[i]]


    # Line and CI colors
    if (is.null(col_dens)){
      col_dens = hcl(h = 240, c = 65, l =70, alpha = 0.2, fixup = TRUE)
    }

    if (is.null(col_ci)){
      col_ci = hcl(h = 210, l = 65, c = 100, alpha = 1)
    }

    # Line and CI colors
    if (is.null(col_line)){
      col_line = "darkblue"
    }

    # Range
    x_range = c(obj_list$ci_low[[i]],obj_list$ci_high[[i]])
    x_low = obj_list$ci_low[[i]] - obj_list$ci_low[[i]]/100
    x_high = obj_list$ci_high[[i]] + obj_list$ci_high[[i]]/100

    y_range = range(density_param$y)
    y_low = min(y_range)
    y_high = max(y_range)

    x_ticks = obj_list$model_hat$theta[[i]]


    x_labels =  obj_list$model_hat$process.desc[i]

    # Main Plot
    plot(NA, xlim = x_range, ylim = c(y_low, y_high), xlab = x_labels, ylab = ylab
         , yaxt = 'n' , bty = "n", ann = FALSE)
    win_dim = par("usr")

    par(new = TRUE)

    plot(NA, xlim = x_range, ylim = c(win_dim[3], win_dim[4] + 0.09*(win_dim[4] - win_dim[3])),
         xlab = x_labels, ylab = ylab, xaxt = 'n', yaxt = 'n', bty = "n")
    win_dim = par("usr")


    # Add Title
    x_vec = c(win_dim[1], win_dim[2], win_dim[2], win_dim[1])
    y_vec = c(win_dim[4], win_dim[4],
              win_dim[4] - 0.09*(win_dim[4] - win_dim[3]),
              win_dim[4] - 0.09*(win_dim[4] - win_dim[3]))
    polygon(x_vec, y_vec, col = "grey95", border = NA)
    text(x = mean(c(win_dim[1], win_dim[2])), y = (win_dim[4] - 0.09/2*(win_dim[4] - win_dim[3])), main, cex = 1.3)

    # Add Axes and Box
    lines(x_vec[1:2], rep((win_dim[4] - 0.09*(win_dim[4] - win_dim[3])),2), col = 1)

    ci_region = density_param$x>=obj_list$ci_low[[i]] & density_param$x<=obj_list$ci_high[[i]]
    box()
    lines(density_param$x,density_param$y, type = "l", col = col_line)
    polygon(c(x_low,density_param$x[ci_region],x_high)
            ,c(x_low,density_param$y[ci_region],x_high),
            col=col_dens, border = F)
    lines(rep(obj_list$model_hat$theta[[i]],2), c(win_dim[3],
                                                  win_dim[4] - 0.09*(win_dim[4] - win_dim[3])),
          col = "red", lwd = 2)

  }
  par(mfrow = c(1,1))
}






