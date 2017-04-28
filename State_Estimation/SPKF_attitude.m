function [SPKF] = SPKF_attitude(Sensor, SPKF, EKF, sensParams, tStep, useExpData)
% SPKF - kinematic prediction for orientation
% this estimator uses an MRP formulation of the quaternion in a sigma point
% kalman filter to propagate the state estimate. Only estimates gryo bias
% and quaternion - angular velocity is assumed to be gyro value minus bias

%notation - _k_1 is previous timestep, _k_m is predicted, _k is corrected
%estimate

global g mag
if useExpData
    g_acc = g;
else
    g_acc = -g;
end
    
%unpackage
%states
pos_k_1 = EKF.X_hat.pos_hat;

vel_k_1 = EKF.X_hat.vel_hat;

q_k_1 = SPKF.X_hat.q_hat;

omega_k_1 = SPKF.X_hat.omega_hat;

rotMat = quat2rotmat(q_k_1);

%bias terms
% bias_acc = EKF.X_hat.bias_acc;
bias_gyr = SPKF.X_hat.bias_gyr;
bias_acc = [0;0;0]; %sensParams.bias.acc;

%measurements
u_b_acc = Sensor.acc;
u_b_gyr = Sensor.gyro;
u_b_mag = Sensor.mag;

u_b_gps = Sensor.gps;

u_b_baro = Sensor.baro;

MRP_0 = zeros(3,1); %q_k_1(2:4)/(1+q_k_1(1));

%%
%init covariance for sig pt calcs
% %sig for prediction (process)
% Q_k_1 = tStep*[diag(sensParams.var_gyr)+1/3*diag(sensParams.var_bias_gyr)*tStep^2, -1/2*diag(sensParams.var_bias_gyr)*tStep; 
%               -1/2*diag(sensParams.var_bias_gyr)*tStep, diag(sensParams.var_bias_gyr)]; 
              
Q_k_1 = tStep*diag([sensParams.var_gyr;
                    sensParams.var_bias_gyr]); 

%sig for correct (update)  only use acc if within bounds
if norm(u_b_acc,2) > norm(g,2) + SPKF.accel_bound || norm(u_b_acc,2) < norm(g,2) - SPKF.accel_bound
    R_k = diag([sensParams.var_mag]);
    SPKF.use_acc = 0;
else
    R_k = diag([sensParams.var_mag;
                sensParams.var_acc]);
    SPKF.use_acc = 1;
end



P_k_1_att = SPKF.P_hat;

%construct matrix to find sigma point modifiers
Y = blkdiag(P_k_1_att,Q_k_1,R_k); 

S = chol(Y, 'lower');

L = length(S);

Sigma_pts_k_1 = zeros(L,2*L+1);

% sigma points are generated for MRP error, gyro bias and noise terms
if SPKF.use_acc
    Sigma_pts_k_1(:,1) = [MRP_0; bias_gyr; zeros(12,1)];
else
    Sigma_pts_k_1(:,1) = [MRP_0; bias_gyr; zeros(9,1)];
end

q_k_1_err = zeros(4,2*L+1);
q_k_1_sig = zeros(4,2*L+1);

q_k_1_sig(:,1) = q_k_1;
%can probably speed most of this up by using lower triang' property of
%cholesky decomposition.
% this loop generates sigma points for estimated MRP and bias and generates
% the associated quaternion SPs as well

%break down loops to take advantage of lower triang properties of chol
% sigma point gen
lambda = SPKF.alpha^2*(L+SPKF.kappa)-L;

a = SPKF.a;
f = 2*(a+1);
for ii = 1:6
    
    %make sigma points
    Sigma_pts_k_1(1:6,ii+1) = Sigma_pts_k_1(1:6,1) + sqrt(L+lambda)*S(1:6,ii);
    Sigma_pts_k_1(1:6,L+ii+1) = Sigma_pts_k_1(1:6,1) - sqrt(L+lambda)*S(1:6,ii);
    
    Sigma_pts_k_1(7:end,ii+1) = Sigma_pts_k_1(7:end,1);
    Sigma_pts_k_1(7:end,L+ii+1) = Sigma_pts_k_1(7:end,1);
    
end

for ii = 7:L
    %make sigma points
    Sigma_pts_k_1(:,ii+1) = Sigma_pts_k_1(:,1); 
    Sigma_pts_k_1(:,L+ii+1) = Sigma_pts_k_1(:,1);
     
end

for ii = 7:L
    Sigma_pts_k_1(ii,ii+1) = Sigma_pts_k_1(ii,ii+1) + sqrt(L+lambda)*S(ii,ii);
    Sigma_pts_k_1(ii,L+ii+1) = Sigma_pts_k_1(ii,L+ii+1) - sqrt(L+lambda)*S(ii,ii);
end

% quat sigma point gen
for ii = 1:7    
    %convert MRP sigma points into quaternions by crassidis' chose a = f = 1
%     eta_k_d_pos = (1-Sigma_pts_k_1(1:3,ii+1)'*Sigma_pts_k_1(1:3,ii+1))/(1+Sigma_pts_k_1(1:3,ii+1)'*Sigma_pts_k_1(1:3,ii+1));
%     eta_k_d_neg = (1-Sigma_pts_k_1(1:3,L+ii+1)'*Sigma_pts_k_1(1:3,L+ii+1))/(1+Sigma_pts_k_1(1:3,L+ii+1)'*Sigma_pts_k_1(1:3,L+ii+1));
%     
%     q_k_1_err(:,ii+1) = [eta_k_d_pos; (1+eta_k_d_pos)*Sigma_pts_k_1(1:3,ii+1)]; %positive error quaternion
%     q_k_1_err(:,L+ii+1) = [eta_k_d_neg; (1+eta_k_d_neg)*Sigma_pts_k_1(1:3,L+ii+1)]; %neg error quaternion
    sigNorm_pos= norm(Sigma_pts_k_1(1:3,ii+1),2);
    sigNorm_neg = norm(Sigma_pts_k_1(1:3,L+ii+1),2);
    eta_k_d_pos = (-a*sigNorm_pos^2 + f*sqrt(f^2 + (1-a^2)*sigNorm_pos^2))/(f^2+sigNorm_pos^2);
    eta_k_d_neg = (-a*sigNorm_neg^2 + f*sqrt(f^2 + (1-a^2)*sigNorm_neg^2))/(f^2+sigNorm_neg^2);
    
    q_k_1_err(:,ii+1) = [eta_k_d_pos; (a+eta_k_d_pos)/f*Sigma_pts_k_1(1:3,ii+1)]; %positive error quaternion
    q_k_1_err(:,L+ii+1) = [eta_k_d_neg; (a+eta_k_d_neg)/f*Sigma_pts_k_1(1:3,L+ii+1)]; %neg error quaternion
    
    q_k_1_sig(:,ii+1) = quatmultiply(q_k_1_sig(:,1),q_k_1_err(:,ii+1)); %compute quaternion sigma pts
    q_k_1_sig(:,L+ii+1) = quatmultiply(q_k_1_sig(:,1),q_k_1_err(:,L+ii+1));
    
%     q_k_1_sig(:,ii+1) = q_k_1_sig(:,ii+1)/norm(q_k_1_sig(:,ii+1)); %renorm just incase
%     q_k_1_sig(:,L+ii+1) = q_k_1_sig(:,L+ii+1)/norm(q_k_1_sig(:,L+ii+1));
end 

for ii = 8:L
    q_k_1_sig(:,ii+1) = q_k_1_sig(:,7+1); %compute quaternion sigma pts
    q_k_1_sig(:,L+ii+1) = q_k_1_sig(:,L+7+1);
end


q_k_m_sig = zeros(4,2*L+1);
q_k_err = zeros(4,2*L+1);
Sigma_pts_k_m = zeros(L,2*L+1);
omega_sig = zeros(3,2*L+1); %angular velocity sigma points are separate from rest as omega isnt estimated.

%this loop propagates (predict) the states using sigma points
for ii = [1:10, (17+SPKF.use_acc*3):(25+SPKF.use_acc*3)]
    %use discretized quat equation to calculate initial quat estimates
    %based on error
    %first calc estimated angular vel with sigma pt modified bias terms
    omega_sig(:,ii) = u_b_gyr - Sigma_pts_k_1(4:6,ii) - Sigma_pts_k_1(7:9,ii); %angular velocity

    %estimate orientation using estimated ang vel - Hamilton conv
    psi_norm = norm(omega_sig(:,ii),2);
    psi_k_p = sin(0.5*psi_norm*tStep)*omega_sig(:,ii)/psi_norm;
    
    Omega_k_p = [cos(0.5*psi_norm*tStep), -psi_k_p';
                  psi_k_p, cos(0.5*psi_norm*tStep)*eye(3)-cross_mat(psi_k_p)];
%               
%     %estimate orientation using estimated ang vel - Fiona conv
%     psi_norm = norm(omega_sig(:,ii),2);
%     psi_k_p = sin(-0.5*psi_norm*tStep)*omega_sig(:,ii)/psi_norm;
%     
%     Omega_k_p = [cos(-0.5*psi_norm*tStep), -psi_k_p';
%                   psi_k_p, cos(-0.5*psi_norm*tStep)*eye(3)+cross_mat(psi_k_p)]; % this is fionas way
    
    q_k_m_sig(:,ii) = Omega_k_p*q_k_1_sig(:,ii); %predicted quaternion sigma points
%     q_k_m_sig(:,ii) = q_k_m_sig(:,ii)/norm(q_k_m_sig(:,ii)); %renorm just incase
    
    q_k_err(:,ii) = quatmultiply([q_k_m_sig(1,1);-q_k_m_sig(2:4,1)],q_k_m_sig(:,ii)); %convert back to error
    %orientation propagated values
    
%     Sigma_pts_k_m(1:3,ii) = q_k_err(2:4,ii)/(1+q_k_err(1,ii)); %convert quat error to MRP
     Sigma_pts_k_m(1:3,ii) = f*q_k_err(2:4,ii)/(a+q_k_err(1,ii)); %convert quat error to MRP
    
    Sigma_pts_k_m(4:6,ii) = Sigma_pts_k_1(4:6,ii); %no noise terms to add.
    Sigma_pts_k_m(13:end,ii) = Sigma_pts_k_1(13:end,ii);
end


%this loop propagates (predict) the states using sigma points
for ii = [11:(16+SPKF.use_acc*3), (26+SPKF.use_acc*3):(31+SPKF.use_acc*3*2)]
    % use lower triang to skip a bunch.
    q_k_m_sig(:,ii) = q_k_m_sig(:,1); %predicted quaternion sigma points
    
    Sigma_pts_k_m(1:3,ii) = Sigma_pts_k_m(1:3,1); %convert quat error to MRP
    
    Sigma_pts_k_m(4:6,ii) = Sigma_pts_k_1(4:6,ii) + tStep*Sigma_pts_k_1(10:12,ii) ;
    Sigma_pts_k_m(13:end,ii) = Sigma_pts_k_1(13:end,ii);
end



%find state and covariance predictions
X_k_m = 1/(L+lambda)*(lambda*Sigma_pts_k_m(1:6,1)+0.5*sum(Sigma_pts_k_m(1:6,2:2*L+1),2));

P_k_m = (lambda/(L+lambda)+(1-SPKF.alpha^2+SPKF.beta))*((Sigma_pts_k_m(1:6,1)-X_k_m(1:6))*(Sigma_pts_k_m(1:6,1)-X_k_m(1:6))');
for ii = 2:2*L+1
    P_k_m = P_k_m+1/(L+lambda)*(0.5*(Sigma_pts_k_m(1:6,ii)-X_k_m(1:6))*(Sigma_pts_k_m(1:6,ii)-X_k_m(1:6))');
end 

% q_k_m_upd(1) = (1-X_k_m(1:3)'*X_k_m(1:3))/(1+X_k_m(1:3)'*X_k_m(1:3));
% %this is wrong as it uses a =f =1
% 
% q_k_m_upd(2:4,1) = (1+q_k_m_upd(1))*X_k_m(1:3);
% 
% 
% q_hat_k_m = quatmultiply(q_k_m_sig(:,1),q_k_m_upd);

SPKF.X_hat.X_k_m = X_k_m;
%%
%measurement sigma and correct
% bound so if there's large acceleration (besides gravity) dont use
if ~SPKF.use_acc
    %only use magnetometer
    
    Sigma_Y = zeros(3,2*L+1);
    %do sig 1 first and then reuse where possible
    rotMat = quat2rotmat(q_k_m_sig(:,1));
    Sigma_Y(1:3,1) = rotMat'*(mag); %magnetometer
%     Sigma_Y(1:3,1) = Sigma_Y(1:3,1)/norm(Sigma_Y(1:3,1));
    %exact same
    for ii = [1, 11:13, 26:28]
        Sigma_Y(1:3,ii) = Sigma_Y(1:3,1); 
        
    end
    %same rotation but add noise
    for ii = [1, 14:16, 29:31]
        Sigma_Y(1:3,ii) = Sigma_Y(1:3,1) + Sigma_pts_k_m(13:15,ii); %magnetometer
%         Sigma_Y(1:3,ii) = Sigma_Y(1:3,ii)/norm(Sigma_Y(1:3,ii));
    end
    %diff rotation and noise
    for ii = [2:10, 17:25]
        rotMat = quat2rotmat(q_k_m_sig(:,ii));       
        Sigma_Y(1:3,ii) = rotMat'*(mag) + Sigma_pts_k_m(13:15,ii); %magnetometer        
%         Sigma_Y(1:3,ii) = Sigma_Y(1:3,ii)/norm(Sigma_Y(1:3,ii));
    end
    
else
    %use both mag and accel
    
    Sigma_Y = zeros(6,2*L+1);

    %do sig 1 first and then reuse where possible
    rotMat = quat2rotmat(q_k_m_sig(:,1));
    Sigma_Y(1:3,1) = rotMat'*(mag); %magnetometer
    Sigma_Y(4:6,1) = rotMat'*([0;0;-g_acc]); %accel
%     Sigma_Y(1:3,1) = Sigma_Y(1:3,1)/norm(Sigma_Y(1:3,1));
%     Sigma_Y(4:6,1) = Sigma_Y(4:6,1)/norm(Sigma_Y(4:6,1)); %accel
    %exact same
    for ii = [1, 11:13, 29:31]
        Sigma_Y(1:3,ii) = Sigma_Y(1:3,1);
        Sigma_Y(4:6,ii) = Sigma_Y(4:6,1);
    end
    %same rotation but add noise mag
    for ii = [14:16, 32:34]
        Sigma_Y(1:3,ii) = Sigma_Y(1:3,1) + Sigma_pts_k_m(13:15,ii); %magnetometer
%         Sigma_Y(1:3,ii) = Sigma_Y(1:3,ii)/norm(Sigma_Y(1:3,ii));
        Sigma_Y(4:6,ii) = Sigma_Y(4:6,1);
    end
    %same rotation but add noise acc
    for ii = [17:19, 35:37]
        Sigma_Y(1:3,ii) = Sigma_Y(1:3,1); %magnetometer
        Sigma_Y(4:6,ii) = Sigma_Y(4:6,1) + Sigma_pts_k_m(16:18,ii);
%         Sigma_Y(4:6,ii) = Sigma_Y(4:6,ii)/norm(Sigma_Y(4:6,ii));
    end
    %diff rotation
    for ii = [2:10, 20:28]
        rotMat = quat2rotmat(q_k_m_sig(:,ii));       
        Sigma_Y(1:3,ii) = rotMat'*(mag); %+ Sigma_pts_k_m(13:15,ii); %magnetometer    
        Sigma_Y(4:6,ii) = rotMat'*([0;0;-g_acc]);% + bias_acc + Sigma_pts_k_m(16:18,ii);
%         Sigma_Y(1:3,ii) = Sigma_Y(1:3,ii)/norm(Sigma_Y(1:3,ii));
%         Sigma_Y(4:6,ii) = Sigma_Y(4:6,ii)/norm(Sigma_Y(4:6,ii));
    end
    

    
end


y_k_hat = 1/(L+lambda)*(lambda*Sigma_Y(:,1)+0.5*sum(Sigma_Y(:,2:2*L+1),2));

%now find matrices needed for kalman gain

V_k = (lambda/(L+lambda)+(1-SPKF.alpha^2+SPKF.beta))*(Sigma_Y(:,1)-y_k_hat)*(Sigma_Y(:,1)-y_k_hat)';
for ii = 2:2*L+1
    V_k = V_k+.5/(L+lambda)*(Sigma_Y(:,ii)-y_k_hat)*(Sigma_Y(:,ii)-y_k_hat)';
end
% V_k = V_k;

U_k = (lambda/(L+lambda)+(1-SPKF.alpha^2+SPKF.beta))*(Sigma_pts_k_m(1:6,1)-X_k_m(1:6))*(Sigma_Y(:,1)-y_k_hat)';

for ii =2:2*L+1
    U_k = U_k + .5/(L+lambda)*(Sigma_pts_k_m(1:6,ii)-X_k_m(1:6))*(Sigma_Y(:,ii)-y_k_hat)';
end

%kalman gain
K_k = U_k/V_k;

SPKF.K_k = K_k;
    %normalize mag and accel measurements now
%     u_b_acc = u_b_acc/norm(u_b_acc);
%     u_b_mag = u_b_mag/norm(u_b_mag);
%     y_k_hat(1:3) = y_k_hat(1:3)/norm(y_k_hat(1:3));
%     if SPKF.use_acc
%         y_k_hat(4:6) = y_k_hat(4:6)/norm(y_k_hat(4:6));
%     end

if SPKF.use_acc
    DX_k = X_k_m + K_k*([u_b_mag; u_b_acc] - y_k_hat);
%     DX_k = K_k*([u_b_mag; u_b_acc] - y_k_hat);
    
    SPKF.innovation = [u_b_mag; u_b_acc] - y_k_hat;
    SPKF.innov_cov = V_k;
    SPKF.K_k = K_k;
else   
    DX_k = X_k_m + K_k*(u_b_mag - y_k_hat);
    
%     DX_k = K_k*(u_b_mag - y_k_hat);
    
    SPKF.innovation = [u_b_mag;zeros(3,1)] - [y_k_hat;zeros(3,1)];
    SPKF.innov_cov = blkdiag(V_k, zeros(3));
    SPKF.K_k = [K_k, zeros(6,3)];
end

SPKF.X_hat.DX_k = DX_k;

SPKF.X_hat.bias_gyr = DX_k(4:6); %X_k_m(4:6) + DX_k(4:6);
% SPKF.X_hat.bias_gyr = X_k_m(4:6) + DX_k(4:6);



SPKF.X_hat.omega_hat = u_b_gyr - SPKF.X_hat.bias_gyr; %ang vel is just gyro minus bias

%need to convert MRP to quaternions

% q_k_upd(1) = (1-DX_k(1:3)'*DX_k(1:3))/(1+DX_k(1:3)'*DX_k(1:3));
% 
% q_k_upd(2:4,1) = (1+q_k_upd(1))*DX_k(1:3);

pNorm = norm(DX_k(1:3),2);
q_k_upd(1) = (-a*pNorm^2 + f*sqrt(f^2+(1-a^2)*pNorm^2))/(f^2+pNorm^2);

q_k_upd(2:4,1) = (a+q_k_upd(1))/f*DX_k(1:3);


SPKF.X_hat.q_hat = quatmultiply(q_k_m_sig(:,1),q_k_upd);

SPKF.X_hat.q_hat =SPKF.X_hat.q_hat/norm(SPKF.X_hat.q_hat);


upd =  K_k*V_k*K_k';
P_hat = P_k_m - upd;


SPKF.P_hat = 0.5*(P_hat + P_hat');