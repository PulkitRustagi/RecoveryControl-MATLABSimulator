function [ Plot ] = hist2plot( Hist )
%UNTITLED2 Summary of this function goes here
%   Detailed explanation goes here

Plot.times = Hist.times;

temp = struct2cell(Hist.propStates);
Plot.propRpms = [temp{1,:}];
Plot.propRpmDerivs = [temp{2,:}];

temp = struct2cell(Hist.poses);
Plot.posns = [temp{1,:}];
Plot.eulerAngles = [temp{3,:}];
Plot.quaternions = [temp{2,:}];
Plot.quaternionDerivs = Hist.stateDerivs(10:13,:);

temp = struct2cell(Hist.twists);
Plot.angVels = [temp{4,:}];
Plot.linVels = [temp{1,:}];

Plot.posnDerivs = Hist.stateDerivs(7:9,:);
Plot.bodyAccs = Hist.stateDerivs(1:3,:);

temp = struct2cell(Hist.contacts);
% Plot.normalForces = [temp{5,:}];
Plot.normalForces = reshape([temp{5,:}],[4,size(temp,2)]);

temp = struct2cell(Hist.controls);
Plot.errEulers = [temp{5,:}];
Plot.desEulers = [temp{13,:}];
Plot.desYawDerivs = [temp{14,:}];

%% Simulate accelerometer data
global g
Plot.accelerometers = zeros(3,size(Plot.quaternions,2));
for iData = 1:size(Plot.quaternions,2)
    
    rotmat = quat2rotmat(Plot.quaternions(:,iData));
    Plot.accelerometers(:,iData) = invar2rotmat('x',pi)*(rotmat*[0;0;g] + Plot.bodyAccs(:,iData) + cross(Plot.angVels(:,iData),Plot.linVels(:,iData)))/g;
end

%% Add noise to accelerometer data
load('/home/thread/fmchui/Spiri/Collison Experiments/2016_02_25/MATLAB_processed_data/sensor_covs.mat');
numSamples = size(Hist.times,1);
numStates = 3;
sigma = C_accel; %Covariance matrix
R = chol(sigma);
noise = randn(numSamples,numStates)*R;
Plot.accelerometersNoisy = Plot.accelerometers + noise';

%% Simulate gyroscope data
Plot.gyros = rad2deg(Plot.angVels);

%% Add noise to gyroscope data
numSamples = size(Hist.times,1);
numStates = 3;
sigma = C_gyro; %Covariance matrix
R = chol(sigma);
noise = randn(numSamples,numStates)*R;
Plot.gyrosNoisy = Plot.gyros + noise';


end
