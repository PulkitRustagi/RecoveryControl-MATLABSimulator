function [SPKF] = initSPKF(Est_ICs)
%estimator constants
SPKF.kappa = -2; % SPKF scaling factor

%initial states ang_vel, quat, gyro bias
SPKF.X_hat.q_hat = Est_ICs.q;
SPKF.X_hat.omega_hat = Est_ICs.omega;
SPKF.X_hat.bias_gyr = Est_ICs.bias_gyr;
%initial covariance - contains variance for MRP and gyr bias. variance in
%ang vel is the noise value
SPKF.P_hat = Est_ICs.P_init_att([1:3,5:7],[1:3,5:7]); % initial covariance 




SPKF.accel_bound = 1; % +/- how much larger thna gravity before not used in update

SPKF.use_acc = 1; % whether or not accelerometer reading is used in update