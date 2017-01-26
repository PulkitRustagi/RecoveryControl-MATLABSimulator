function [SPKF_full] = SPKF_full_state(Sensor, SPKF_full, sensParams, tStep, iSim)
% SPKF_full - kinematic prediction for orientation
% this estimator uses an MRP formulation of the quaternion in a sigma point
% kalman filter to propagate the state estimate. Only estimates gryo bias
% and quaternion - angular velocity is assumed to be gyro value minus bias

%notation - _k_1 is previous timestep, _k_m is predicted, _k is corrected
%estimate

global g mag
%unpackage
%states
pos_k_1 = SPKF_full.X_hat.pos_hat;

vel_k_1 = SPKF_full.X_hat.vel_hat;

q_k_1 = SPKF_full.X_hat.q_hat;

omega_k_1 = SPKF_full.X_hat.omega_hat;

rotMat = quat2rotmat(q_k_1);

%bias terms
% bias_acc = SPKF_full.X_hat.bias_acc;
bias_gyr = SPKF_full.X_hat.bias_gyr;
bias_acc = sensParams.bias.acc;

%measurements
u_b_acc = Sensor.acc;
u_b_gyr = Sensor.gyro;
u_b_mag = Sensor.mag;

u_b_gps = Sensor.gps;

u_b_baro = Sensor.baro;

lat_0 = sensParams.gps_init(1);
long_0 = sensParams.gps_init(2);
height_0 = sensParams.gps_init(3);
Me  = sensParams.gps_init(4);
Ne  = sensParams.gps_init(5);

baro_0 = sensParams.baro_init;

MRP_0 = zeros(3,1); %q_k_1(2:4)/(1+q_k_1(1));

%%
%init covariance for sig pt calcs
%sig for prediction (process)
Q_k_1 = diag([sensParams.var_acc;
              sensParams.var_gyr;
              ones(3,1)*sensParams.var_bias_acc
              ones(3,1)*sensParams.var_bias_gyr]); 

%sig for correct (update)        
R_k = diag([sensParams.var_mag
            sensParams.var_gps
            sensParams.var_baro]);
        
P_k_1 = SPKF_full.P_hat;

%construct matrix to find sigma point modifiers
Y = blkdiag(P_k_1,Q_k_1,R_k); 

S = chol(Y, 'lower');

L = length(S);

Sigma_pts_k_1 = zeros(L,2*L+1);

% sigma points are generated for MRP error, gyro bias and noise terms
Sigma_pts_k_1(:,1) = [pos_k_1; vel_k_1; MRP_0; bias_acc; bias_gyr; zeros(21,1)];

q_k_1_err = zeros(4,2*L+1);
q_k_1_sig = zeros(4,2*L+1);

q_k_1_sig(:,1) = q_k_1;
%can probably speed most of this up by using lower triang' property of
%cholesky decomposition.
% this loop generates sigma points for estimated MRP and bias and generates
% the associated quaternion SPs as well
for ii = 1:L
    
    %make sigma points
    Sigma_pts_k_1(:,ii+1) = Sigma_pts_k_1(:,1) + sqrt(L+SPKF_full.kappa)*S(:,ii);
    Sigma_pts_k_1(:,L+ii+1) = Sigma_pts_k_1(:,1) - sqrt(L+SPKF_full.kappa)*S(:,ii);
    
    %convert MRP sigma points into quaternions by crassidis' chose a = f = 1
    eta_k_d_pos = (1-Sigma_pts_k_1(7:9,ii+1)'*Sigma_pts_k_1(7:9,ii+1))/(1+Sigma_pts_k_1(7:9,ii+1)'*Sigma_pts_k_1(7:9,ii+1));
    eta_k_d_neg = (1-Sigma_pts_k_1(7:9,L+ii+1)'*Sigma_pts_k_1(7:9,L+ii+1))/(1+Sigma_pts_k_1(7:9,L+ii+1)'*Sigma_pts_k_1(7:9,L+ii+1));
    
    q_k_1_err(:,ii+1) = [eta_k_d_pos; (1+eta_k_d_pos)*Sigma_pts_k_1(7:9,ii+1)]; %positive error quaternion
    q_k_1_err(:,L+ii+1) = [eta_k_d_neg; (1+eta_k_d_neg)*Sigma_pts_k_1(7:9,L+ii+1)]; %neg error quaternion
    
    q_k_1_sig(:,ii+1) = quatmultiply(q_k_1_err(:,ii+1),q_k_1_sig(:,1)); %compute quaternion sigma pts
    q_k_1_sig(:,L+ii+1) = quatmultiply(q_k_1_err(:,L+ii+1),q_k_1_sig(:,1));
end 


q_k_m_sig = zeros(4,2*L+1);
q_k_err = zeros(4,2*L+1);
Sigma_pts_k_m = zeros(L,2*L+1);
omega_sig = zeros(3,2*L+1); %angular velocity sigma points are separate from rest as omega isnt estimated.

%this loop propagates (predict) the states using sigma points
for ii = 1:2*L+1
    %use discretized quat equation to calculate initial quat estimates
    %based on error
    %first calc estimated angular vel with sigma pt modified bias terms
    omega_sig(:,ii) = u_b_gyr - Sigma_pts_k_1(13:15,ii) - Sigma_pts_k_1(19:21,ii); %angular velocity

    %estimate orientation using estimated ang vel
    psi_norm = norm(omega_sig(:,ii),2);
    psi_k_p = sin(-0.5*psi_norm*tStep)*omega_sig(:,ii)/psi_norm;
    
    Omega_k_p = [cos(-0.5*psi_norm*tStep), -psi_k_p';
                  psi_k_p, cos(-0.5*psi_norm*tStep)*eye(3)+cross_mat(psi_k_p)];
    
    q_k_m_sig(:,ii) = Omega_k_p*q_k_1_sig(:,ii); %predicted quaternion sigma points
    
    q_k_err(:,ii) = quatmultiply(q_k_m_sig(:,ii),[q_k_m_sig(1,1);-q_k_m_sig(2:4,1)]); %convert back to error
    %orientation propagated values
    Sigma_pts_k_m(7:9,ii) = q_k_err(2:4,ii)/(1+q_k_err(1,ii)); %convert quat error to MRP
    
    rotMat = quat2rotmat(q_k_m_sig(:,ii));
    
    %position propagated values
    Sigma_pts_k_m(1:3,ii) = Sigma_pts_k_1(1:3,ii) + tStep*Sigma_pts_k_1(4:6,ii);
    %velocity propagated values
    Sigma_pts_k_m(4:6,ii) = Sigma_pts_k_1(4:6,ii) + tStep*rotMat'*(u_b_acc - Sigma_pts_k_1(10:12,ii) - Sigma_pts_k_1(16:18,ii)) + tStep*[0;0;-g];
    %bias propagated values
    Sigma_pts_k_m(10:15,ii) = Sigma_pts_k_1(10:15,ii) + tStep*Sigma_pts_k_1(22:27,ii) ;
    %noise propagated values - might not actually use these anymore
    Sigma_pts_k_m(16:end,ii) = Sigma_pts_k_1(16:end,ii);
end
%find state and covariance predictions
X_k_m = 1/(L+SPKF_full.kappa)*(SPKF_full.kappa*Sigma_pts_k_m(1:15,1)+0.5*sum(Sigma_pts_k_m(1:15,2:2*L+1),2));

P_k_m = 1/(L+SPKF_full.kappa)*(SPKF_full.kappa*(Sigma_pts_k_m(1:15,1)-X_k_m(1:15))*(Sigma_pts_k_m(1:15,1)-X_k_m(1:15))');
for ii = 2:2*L+1
    P_k_m = P_k_m+1/(L+SPKF_full.kappa)*(0.5*(Sigma_pts_k_m(1:15,ii)-X_k_m(1:15))*(Sigma_pts_k_m(1:15,ii)-X_k_m(1:15))');
end 

%%
%measurement sigma and correct
% only use gps at the GPS udate rate, must be multiple of timestep -
% otherwise wont use properly
if mod(iSim,sensParams.GPS_rate) == 0
    R_k = diag([sensParams.var_mag
                sensParams.var_gps
                sensParams.var_baro]);
    
    Sigma_Y = zeros(9,2*L+1);
    for ii = 1:2*L+1
        rotMat = quat2rotmat(q_k_m_sig(:,ii));       
        Sigma_Y(1:3,ii) = rotMat*(mag) + Sigma_pts_k_m(28:30,ii); %magnetometer    
        
        Sigma_Y(4,ii) = Sigma_pts_k_m(1,ii)/(Me+height_0-Sigma_pts_k_m(3,ii))*180/pi + lat_0 + Sigma_pts_k_m(31,ii);
        Sigma_Y(5,ii) = Sigma_pts_k_m(2,ii)/((Ne+height_0-Sigma_pts_k_m(3,ii))*cos(lat_0*pi/180.0))*180/pi + long_0 + Sigma_pts_k_m(32,ii);
        Sigma_Y(6,ii) = Sigma_pts_k_m(3,ii) + height_0 + Sigma_pts_k_m(33,ii);
        Sigma_Y(7,ii) = Sigma_pts_k_m(4,ii) + Sigma_pts_k_m(34,ii);
        Sigma_Y(8,ii) = Sigma_pts_k_m(5,ii) + Sigma_pts_k_m(35,ii);
        Sigma_Y(9,ii) = 101325*(1-2.25577*10^-5*(Sigma_pts_k_m(3,ii)+height_0))^5.25588 + Sigma_pts_k_m(36,ii);
    end
    

else
    R_k = diag([sensParams.var_mag
                sensParams.var_baro]);
    
    Sigma_Y = zeros(4,2*L+1);
    
    for ii = 1:2*L+1
        rotMat = quat2rotmat(q_k_m_sig(:,ii));       
        Sigma_Y(1:3,ii) = rotMat*(mag) + Sigma_pts_k_m(28:30,ii); %magnetometer       
        Sigma_Y(4,ii) = 101325*(1-2.25577*10^-5*(Sigma_pts_k_m(3,ii)+height_0))^5.25588 + Sigma_pts_k_m(36,ii);
    end
    
end


y_k_hat = 1/(L+SPKF_full.kappa)*(SPKF_full.kappa*Sigma_Y(:,1)+0.5*sum(Sigma_Y(:,2:2*L+1),2));

%now find matrices needed for kalman gain

V_k = SPKF_full.kappa/(L+SPKF_full.kappa)*(Sigma_Y(:,1)-y_k_hat)*(Sigma_Y(:,1)-y_k_hat)';
for ii = 2:2*L+1
    V_k = V_k+.5/(L+SPKF_full.kappa)*(Sigma_Y(:,ii)-y_k_hat)*(Sigma_Y(:,ii)-y_k_hat)';
end
V_k = V_k + R_k;

U_k = SPKF_full.kappa/(L+SPKF_full.kappa)*(Sigma_pts_k_m(1:15,1)-X_k_m(1:15))*(Sigma_Y(:,1)-y_k_hat)';

for ii =2:2*L+1
    U_k = U_k + .5/(L+SPKF_full.kappa)*(Sigma_pts_k_m(1:15,ii)-X_k_m(1:15))*(Sigma_Y(:,ii)-y_k_hat)';
end

%kalman gain
K_k = U_k/V_k;

if mod(iSim,sensParams.GPS_rate) == 0
    DX_k = K_k*([ u_b_mag; u_b_gps; u_b_baro] - y_k_hat);
else   
    DX_k = K_k*([ u_b_mag; u_b_baro] - y_k_hat);
end

SPKF_full.X_hat.pos_hat =  X_k_m(1:3) + DX_k(1:3);

SPKF_full.X_hat.vel_hat =  X_k_m(4:6) + DX_k(4:6);

SPKF_full.X_hat.bias_acc = X_k_m(10:12) + DX_k(10:12);

SPKF_full.X_hat.bias_gyr = X_k_m(13:15) + DX_k(13:15);

SPKF_full.X_hat.omega_hat = u_b_gyr - SPKF_full.X_hat.bias_gyr; %ang vel is just gyro minus bias

%need to convert MRP to quaternions

q_k_upd(1) = (1-DX_k(7:9)'*DX_k(7:9))/(1+DX_k(7:9)'*DX_k(7:9));

q_k_upd(2:4,1) = (1+q_k_upd(1))*DX_k(7:9);



SPKF_full.X_hat.q_hat = quatmultiply(q_k_upd,q_k_m_sig(:,1));

SPKF_full.X_hat.q_hat = SPKF_full.X_hat.q_hat/norm(SPKF_full.X_hat.q_hat);


upd =  K_k*V_k*K_k';
P_hat = P_k_m - upd;


SPKF_full.P_hat = 0.5*(P_hat + P_hat');