function [SRSPKF] = initSRSPKF(Est_ICs)
%estimator constants
SRSPKF.kappa = 0; % SRSPKF scaling factor

%initial states ang_vel, quat, gyro bias
SRSPKF.X_hat.q_hat = Est_ICs.q;
SRSPKF.X_hat.omega_hat = Est_ICs.omega;
SRSPKF.X_hat.bias_gyr = Est_ICs.bias_gyr;

%initial covariance - contains variance for MRP and gyr bias. variance in
%ang vel is the noise value
P_hat = Est_ICs.P_init_att([1:3,5:7],[1:3,5:7]); % initial covariance 


Y = blkdiag(P_hat); 

SRSPKF.S_hat = chol(Y, 'lower'); %set initial cholesky factorization estimate


SRSPKF.accel_bound = 1; % +/- how much larger thna gravity before not used in update

SRSPKF.use_acc = 1; % whether or not accelerometer reading is used in update

SRSPKF.alpha = 1; %dictates spread of sigma points

SRSPKF.beta = 2; %2 is optimal for gaussian noise

