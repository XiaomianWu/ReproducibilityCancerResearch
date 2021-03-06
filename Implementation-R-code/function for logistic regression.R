######### localFDR_cal.R ############################################
#######################################################  
f1 = function(y, lambda, t, freq)
{
  k = length(t);
  k1 = k-1;
  
  support = cumprod( (1-t[1:k1])^(lambda[1:k1]-lambda[2:k]) );
  support = c(1, support);
  
  ss = rep(support, freq);
  lam = rep(lambda, freq);
  
  ss*lam*(1-y)^(lam-1);
}

F1 = function(y, lambda, t, freq)
{
  lam = rep(lambda, freq);
  1 - f1(y, lambda, t, freq)*(1-y)/lam;
}

log.likelihood.tau.total = function(tau, y, z, t, sigma2, freq)
{
  k = length(t);
  k1 = k-1;
  
  lambda = exp(tau) + 1;
  
  sigma.local = lambda[2:k]/(lambda[2:k]-1);
  sigma.local = 1;
  diff = tau[1:(k-1)] - tau[2:k];
  diff = diff/sigma.local;
  
  result = -sum( diff^2 )/2/sigma2;
  
  result2 = f1(y, lambda, t, freq)[z==1];
  result2 = log(result2);
  
  result + sum(result2);
}

sample.tau.one.component = function(i, tau, y, z, t, sigma2, sigma2.mean, freq)
{
  alpha.old = log.likelihood.tau.total(tau, y, z, t, sigma2, freq);
  
  tau.single.old = tau[i];
  tau.single.new = tau.single.old + rnorm( 1, 0, sqrt(sigma2.mean) );
  
  tau[i] = tau.single.new;
  alpha.new = log.likelihood.tau.total(tau, y, z, t, sigma2, freq);
  
  alpha = exp( alpha.new - alpha.old );                 
  #print(c(alpha, alpha.new, alpha))
  if( runif(1) < alpha ) return(tau.single.new)
  else return(tau.single.old);
}


location = function(y, t)
{
  n = length(y);
  ll = numeric(n);
  
  for(i in 1:n) ll[i] = which(t>y[i])[1];
  
  ll <- factor(ll,levels=1:length(t))
  
  ll;
}


localFDR = function(y, k, n.simu, v=.30*k)       #v for prior of sigma2
{
  #the y is a vector of pvalues to be decomposed
  # t is the vector of kots not including 0 but including 1
  
  y = sort(y);
  
  small = 100*.Machine$double.eps;
  y[y<small] = small;
  y[y>1-small] = 1-small;
  
  t = comp.t(y, k);
  n = length(y);  #number of p-value
  
  zeta = 0.0001;
  
  #initial values
  
  pi0 = mean(y>.5)/.5;
  
  tau = rep(.5, k);
  sigma2 = .1;
  
  tau.mean = numeric(k);
  pi0.mean = 0;
  sigma2.mean = sigma2;
  
  pi0.save = numeric(n.simu);
  freq = table( location(y, t) );
  
  lambda = exp(tau) + 1;
  k1 = k-1;
  
  for(i in 1:n.simu)
  {
    fdr = (1-pi0)*f1(y, lambda, t, freq);
    fdr = pi0/(fdr + pi0);
    z = rbinom(n, 1, 1-fdr);           ##
    
    sum.z = sum(z);
    if(i>100) pi0 = rbeta(1, n-sum.z+1, sum.z+1);  ##
    pi0.save[i] = pi0;
    
    for(j in k:1) tau[j] = sample.tau.one.component(j, tau, y, z, t, sigma2, sigma2.mean, freq);      ##
    
    lambda = exp(tau) + 1;
    sigma.local = lambda[2:k]/(lambda[2:k]-1);
    sigma.local = 1;
    diff = tau[1:(k-1)] - tau[2:k];
    diff = diff/sigma.local;
    
    scale = zeta*v + sum( diff^2 );
    scale = scale/(v+k-1);
    
    sigma2 = scale*(k-1+v)/rchisq(1, k-1+v);      #print(sigma2); print(tau);
    ##################################################
    ww = 1/i;
    tau.mean = tau.mean*(1-ww) + tau*ww;
    pi0.mean = pi0.mean*(1-ww) + pi0*ww;
    sigma2.mean = sigma2.mean*(1-ww) + sigma2*ww;
    
    lambda.mean = exp(tau.mean) + 1;
    
    ######################################################
    if(i%%10!=0) next;
    
    fdr = (1-pi0.mean)*f1(y, lambda.mean, t, freq);
    fdr = pi0.mean/(fdr + pi0.mean);
    
    FDR = (1-pi0.mean)*F1(y, lambda.mean, t, freq);
    FDR = 1 - FDR/(FDR + pi0.mean*y);
    #plot(y, f1(y, lambda.mean, t, freq), type="l");
    plot(y, fdr, type="l", xlab='raw pvalue', ylab='local FDR');
    #lines(y, FDR, type="l");
    
    print(i); print("posterior of pi0");
    print(quantile(pi0.save[1:i], c(.025,.50,.975)));
  }
  
  F1.value = F1(y, lambda.mean, t, freq);
  F = pi0.mean*y + (1-pi0.mean)*F1.value;
  NPV = pi0.mean*(1-y)/(1-F);
  
  f.value = pi0.mean + (1-pi0.mean)*f1(y, lambda.mean, t, freq);
  
  fdr
}

#####################################################################################    
comp.t = function(pvalue, k)   #select the knots t based on the quantiles of pavlue
{
  pvalue = sort(pvalue);
  n = length(pvalue);
  
  t=numeric(k);
  for(j in 1:k) t[j] = pvalue[n*j/k];
  t[k] = 1;
  
  start = which(t==1)[1]-1;
  diff = 1 - t[start];
  step = diff/(k-start);
  
  for(i in (start+1):k) t[i] = t[start] + (i-start)*step;
  t;
}

######################################################################################     
raw.pvalues.cal.one = function(x, y)  #pvalues for simple logistic regression
{
  n = nrow(x)
  p = ncol(x)
  
  pvalue = array(0, c(p,2)) #the 1st column is the pvalue 
  #the 2dn column is the probability of regression coefficients being positive                 
  one = rep(1,n)                         
  for(j in 1:p)
  {
    xx = cbind(one, x[,j])
    model = glm.fit(xx, y, family=binomial())       #pvalue based on simple logistic regression    
    pvalue[j,1] = 1 - pchisq(model$null.deviance-model$deviance, df=1)
    pvalue[j,2] = ifelse(model$coefficients[2]>0, 1-pvalue[j,1]/2, pvalue[j,1]/2)
  }
  pvalue       
} 

localFDR.cal = function(x, y, k=40, n.simu=10000, v=40)
{
  result = raw.pvalues.cal.one(x, y) ; hist(result[,1])
  rank1 = rank( result[,1] )     
  
  localFDR.fit = localFDR(result[,1], k, n.simu, v)
  localFDR.fit = localFDR.fit[rank1]   #keep the original order of raw pvalues
  
  result = cbind(localFDR.fit, result[,2]) 
  write.dta(as.data.frame(result), "localFDR_value.dta")
}  

################ logistic_penalized.R #############################################
#############################################################
solve.special = function(lambda, U, t.V, b)  # A = tau * I      Numerical Recipes chapter 2.7
{
  Z = U/lambda;
  H = t.V %*% Z;
  H[row(H)==col(H)] = H[row(H)==col(H)] + 1;
  
  D = b/lambda;
  as.vector(D - Z %*% solve(H, t.V %*% D));
}    

b.update.wide = function(t.x, x, y, b, lambda)  #p>n, more predictors than subjects
{
  p = ncol(x);
  pi1 = plogis(as.vector(x %*% b));
  w = pi1*(1-pi1);
  
  right.side = as.vector( y - pi1 + w * (x %*% b) ); #as.vector( y - pi1 + diag(w)%*%(x %*% b) );
  right.side = as.vector(t.x%*%right.side)
  
  u = numeric(p);
  u[1] = -lambda;
  v = numeric(p);
  
  v[1] = 1;
  U = t(x) * rep(sqrt(w), each=p) #t(x) %*% diag(sqrt(w)), matrix of dimension p by n
  t.V = rbind(t(U), v);
  U = cbind(U, u);
  
  solve.special(lambda, U, t.V, right.side)
}

b.update.high = function(t.x, x, y, b, lambda)  #n>p, more subjects than predictors
{
  p = ncol(x);
  pi1 = plogis(as.vector(x %*% b));
  w = pi1*(1-pi1);
  
  right.side = y - pi1 + as.vector(w * (x %*% b) ); #as.vector( y - pi1 + diag(w)%*%(x %*% b) );    
  right.side = as.vector(t.x%*%right.side)
  
  Q = diag(p)
  Q[1,1] = 0
  left.side = (t.x * rep(w, each=p)) %*% x + lambda * Q   ;   
  solve(left.side, right.side)
}


logistic.penalized = function(x, y, lambda)
  
{                                        #n is the number of subjects
  #p is the number of predictors + intercept                                       
  if(lambda < 1.e-5) lambda = 1.e-5        
  if( is.vector(x) ) x = cbind( rep(1, length(x)), x ) 
  
  n = nrow(x)       
  if(any(x[,1]!=1))  x = cbind( rep(1, n), x )     
  
  p = ncol(x) 
  b = numeric(p)
  t.x = t(x)
  
  repeat
  {
    if(n>p) b.new = b.update.high(t.x, x, y, b, lambda)
    else b.new = b.update.wide(t.x, x, y, b, lambda)
    
    diff = mean( abs(b.new - b) )
    b = b.new;
    
    if(diff < 1.e-8) break;
  }
  
  logit.fitted = as.vector(x %*% b)
  pi1 = plogis(logit.fitted)
  log.likelihood = sum( log(pi1[y==1]) ) + sum( log(1-pi1[y==0]) );
  log.likelihood = log.likelihood/n;
  
  list(b=b, logit.fitted=logit.fitted, log.likelihood=log.likelihood);
}

############ estimation.R #########################################
##################################################### 

r.conditional.bernoulli = function(pi1, k)    #gamma: the log odds ratio, k: number of 1s.
{     
  n = length(pi1)
  repeat
  {
    yy = rbinom(n, 1, pi1)
    if(sum(yy)==k) return(yy)
  }
}

b0.estimate = function(offset1, k)
{               
  func = function(b0)     #increasing function of b0
  {         
    temp = b0 + offset1
    sum(plogis(temp)) - k         
  }
  
  lower = 0
  f0 = func(lower)
  if(f0<0) factor1 = 1
  else factor1 = -1
  
  repeat
  {
    upper = lower + factor1
    f1 = func(upper)  
    if(f0*f1<0) break
    lower = upper
    factor1 = factor1*2
  }   
  
  if(factor1 > 0) b0 = uniroot(func, lower=lower, upper=upper, tol = 100*.Machine$double.eps^0.25)$root
  else b0 = uniroot(func, lower=upper, upper=lower, tol = 100*.Machine$double.eps^0.25)$root
  plogis( b0 + offset1)      
}   

################################################################################################
likelihood.one = function(x, y, localFDR.value, theta)
{   
  k = sum(y)
  p = ncol(x)
  gene.selected = (runif(p)<1-localFDR.value[,1])
  
  b = rnorm(p, mean=0, sd=theta) 
  sign1 = ifelse(runif(p)<localFDR.value[,2], 1, -1) 
  b = abs(b) * sign1     
  
  gamma1 = as.vector(x[, gene.selected] %*% b[gene.selected])
  pi1 = b0.estimate(gamma1, k) 
  #plot(y, pi1)
  mean1 = sum(pi1)
  sd1 = sqrt(sum(pi1*(1-pi1)))
  denominator = pnorm(k+.5, mean1, sd1) - pnorm(k-.5, mean1, sd1)  #normal approximation
  numerator = prod(dbinom(y,1,pi1)) 
  
  numerator / denominator 
}    


model.estimation = function(x, y, n.simu=5000)
{            
  localFDR.value = as.matrix(read.dta("localFDR_value.dta"))  
  
  k = sum(y)   
  func = function(log.theta) 
  { 
    theta = exp(log.theta)
    value = mean( replicate(n.simu, likelihood.one(x, y, localFDR.value, theta)) )
    value = value / theta^.333 
    print(c(theta, value))
    value
  }
  result = optimize(f=func, lower=log(1.e-6), upper = log(1), maximum = TRUE) 
  theta = exp(result$maximum)
  
  print("The theta estimate is"); print(theta)         
  dump('theta',"theta_estimate_dumped")
  theta           
}  


############# Prediction.R ###################################################
##################################################################
bootstrap.draw = function(x, k, localFDR.value, theta)
{  
  p = ncol(x)
  gene.selected = (runif(p)<1-localFDR.value[,1])
  
  b = rnorm(p, mean=0, sd=theta) 
  sign1 = ifelse(runif(p)<localFDR.value[,2], 1, -1) 
  b = abs(b) * sign1     
  
  gamma1 = as.vector(x[, gene.selected] %*% b[gene.selected])
  pi1 = (glm(y~1+offset(gamma1), family=binomial, epsilon=1.e-6))$fitted.values
  
  yy = r.conditional.bernoulli(pi1, k)
  list(pi1=pi1, y=yy)
}
# For Prediction
pena.logit = function(x, y, q, tau)
{        
  raw.pvalues = raw.pvalues.cal.one(x, y)[,1]
  r1 = order(raw.pvalues)[1:q]  
  
  model = logistic.penalized(x[,r1], y, lambda=1/tau^2)
  list(b=model$b, fitted=plogis(model$logit.fitted), gene.selected=r1)
}

prediction.error.make = function(x, y, q, n.simu)
{
  localFDR.value = as.matrix(read.dta("localFDR_value.dta"))     
  source("theta_estimate_dumped")
  
  k = sum(y)
  result = numeric(n.simu)
  function(log.tau)
  {
    tau = exp(log.tau)
    risk = 0
    for(i in 1:n.simu)
    {
      obj = bootstrap.draw(x, k, localFDR.value, theta)  #conditional draw
      pi1.fitted = pena.logit(x, obj$y, q, tau)$fitted  
      result[i] = mean((obj$pi1- pi1.fitted)^2) + mean(obj$pi1*(1-obj$pi1)) 
    }
    result =  mean(result)
    print(c(tau, result))
    result
  }
}  

bootstrap.prediction = function(x, y, q)  #penalized logistic regression
{ 
  n.simu=1000       #simulation sample size
  prediction.error = prediction.error.make(x, y, q, n.simu)          
  
  obj = optimize(prediction.error, c(log(.001), log(5)), maximum=FALSE)   #returns the optimal penalty
  
  print(c("The optimal tau is ", exp(obj$minimum)))
  print(c("The prediction error is ", obj$objective)) 
}


############ Misselaneous #####################################
###############################################
CV.pred = function(x, y, q, tau)
{
  fitted.cross = numeric(length(y))
  
  for(i in 1:length(y))
  {
    result = pena.logit(x[-i,], y[-i], q, tau) 
    print(result)          
    
    xx = x[i, result$gene.selected]   
    xx = c(1, xx)  
    fitted.cross[i] = plogis(sum(xx * result$b))
    print(c(i, y[i], fitted.cross[i]))
  }   
  
  plot(y, fitted.cross)
  
  print(mean((y-fitted.cross)^2)) 
  fitted.cross  
}    