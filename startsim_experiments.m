% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% % Monte Carlo Simulation of Crash Recovery using Fuzzy Logic  %
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% %   RPM max acceleration 70,000 rpm/s
% % For all trials:
% %   Thrust coefficient: 8.7e-8
% %   Drag coefficient:   8.7e-9
% %   Friction coefficient: 0.3
% %   Angle error to body rate gain: 20.0
% %   Proportional gains only for body rate control (20 for {p,q}, 2 for {r})
% %   Fuzzy logic output between -1 and 1 
% %       -multiplied by 9.81 for Control.accelRef if TOWARD the wall
% %       -multiplied by 9.81/2 if AWAY from the wall

% % See /Controller/checkrecoverystage.m for recovery stage switch conditions
% % See /Controller/controllerrecovery.m for recovery method
% % See /Results/plot_monte.m for plotting results
% % See /Fuzzy\Logic/initfuzzylogicprocess.m for fuzzy logic parameters

tic
clear all;
global g timeImpact globalFlag
 
ImpactParams = initparams_navi;
 
SimParams.recordContTime = 0;
SimParams.useFaesslerRecovery = 1;%Use Faessler recovery
SimParams.useRecovery = 1; 
SimParams.timeFinal = 3;
tStep = 1/200;
 
num_iter = 10;
 
IC = initIC; % dummy initialization
Monte = initmontecarlo(IC);
 
for k = 1:num_iter
    display(k);
 
    ImpactParams.frictionModel.muSliding = 0.3; %kinetic friction
    ImpactParams.wallLoc = 0.0; 
    ImpactParams.wallPlane = 'YZ';
    ImpactParams.timeDes = 0.5; % irrelevant
    ImpactParams.frictionModel.velocitySliding = 1e-4; % m/s
    timeImpact = 10000; % irrelevant
 
    IC = initIC;
    Control = initcontrol;
    PropState = initpropstate;
    Setpoint = initsetpoint;
    [Contact, ImpactInfo] = initcontactstructs;
    localFlag = initflags; % for contact analysis, irrelevant
 
    % Initialize Fuzzy Logic Process
    [FuzzyInfo, PREIMPACT_ATT_CALCSTEPFWD] = initfuzzyinput();
    
    % rotation matrix
    ImpactIdentification = initimpactidentification;
    
    % Randomized ICs    
    % World X velocity at impact
    xVelocity = rand*2.6 + 0.7; % randomize incoming velocity
    Control.twist.posnDeriv(1) = xVelocity; 
    % -11 to 23, 0.7 to 3.3
    IC.attEuler = [0;deg2rad(34*(rand-11/34));deg2rad(45*rand)]; % randomize initial Euler angles

    % starts next to the wall 5 meter up
    IC.posn = [-0.32; 0; 5];                             
    Setpoint.posn(3) = IC.posn(3);                                        
    xAcc = 0; %don't change                                                
    rotMat = quat2rotmat(angle2quat(-(IC.attEuler(1)+pi),IC.attEuler(2),IC.attEuler(3),'xyz')');
 
    SimParams.timeInit = 0; 
    Setpoint.head = IC.attEuler(3);
    Setpoint.time = SimParams.timeInit;
    Setpoint.posn(1) = IC.posn(1);
    Trajectory = Setpoint;
 
    IC.linVel =  rotMat*[xVelocity;0;0];

    Experiment.propCmds = [];
    Experiment.manualCmds = [];
 
    globalFlag.experiment.rpmChkpt = zeros(4,1);
    globalFlag.experiment.rpmChkptIsPassed = zeros(1,4);
 
    [IC.rpm, Control.u] = initrpm(rotMat, [xAcc;0;0]); %Start with hovering RPM
 
    PropState.rpm = IC.rpm;
 
    % Initialize state and kinematics structs from ICs
    [state, stateDeriv] = initstate(IC, xAcc);
    [Pose, Twist] = updatekinematics(state, stateDeriv);
 
    % Initialize sensors
    Sensor = initsensor(rotMat, stateDeriv, Twist);
 
    % Initialize history 
    Hist = inithist(SimParams.timeInit, state, stateDeriv, Pose, Twist, Control, PropState, Contact, localFlag, Sensor);
 
    %% Simulation Loop
    for iSim = SimParams.timeInit:tStep:SimParams.timeFinal-tStep
 
        %% Update Sensors
        rotMat = quat2rotmat(Pose.attQuat);
        Sensor.accelerometer = (rotMat*[0;0;g] + stateDeriv(1:3) + cross(Twist.angVel,Twist.linVel))/g; %in g's
        Sensor.gyro = Twist.angVel;
 
        %% Impact Detection    
        [ImpactInfo, ImpactIdentification] = detectimpact(iSim, ImpactInfo, ImpactIdentification,...
                                                          Sensor,Hist.poses,PREIMPACT_ATT_CALCSTEPFWD);
        [FuzzyInfo] = fuzzylogicprocess(iSim, ImpactInfo, ImpactIdentification,...
                                        Sensor, Hist.poses(end), SimParams, Control, FuzzyInfo);
 
        % Calculate accelref in world frame based on FuzzyInfo.output, estWallNormal
        if sum(FuzzyInfo.InputsCalculated) == 4 && Control.accelRefCalculated == 0;
                Control.accelRef = calculaterefacceleration(FuzzyInfo.output, ImpactIdentification.wallNormalWorld);
                Monte.accelRef = [Monte.accelRef; Control.accelRef'];
                Control.accelRefCalculated = 1;
        end
 
        %% Control
        if ImpactInfo.firstImpactDetected %recovery control       
%             if SimParams.useFaesslerRecovery == 1  
                Control = checkrecoverystage(Pose, Twist, Control, ImpactInfo);
                [Control] = computedesiredacceleration(Control, Twist);
 
                % Compute control outputs
                [Control] = controllerrecovery(tStep, Pose, Twist, Control);       
                Control.type = 'recovery';
        else
            Control.recoveryStage = 0;
        end

        %% Propagate Dynamics
        options = getOdeOptions();
        [tODE,stateODE] = ode45(@(tODE, stateODE) dynamicsystem(tODE,stateODE, ...
                                                                tStep,Control.rpm,ImpactParams,PropState.rpm, ...
                                                                Experiment.propCmds),[iSim iSim+tStep],state,options);
        % Reset contact flags for continuous time recording        
        globalFlag.contact = localFlag.contact;
        if SimParams.recordContTime == 0
 
        [stateDeriv, Contact, PropState] = dynamicsystem(tODE(end),stateODE(end,:), ...
                                                         tStep,Control.rpm,ImpactParams, PropState.rpm, ...
                                                         Experiment.propCmds);        
            if sum(globalFlag.contact.isContact)>0
                Contact.hasOccured = 1;
                if ImpactInfo.firstImpactOccured == 0
                    ImpactInfo.firstImpactOccured = 1;
                end
            end
 
        else      
            for j = 1:size(stateODE,1)
                [stateDeriv, Contact, PropState] = dynamicsystem(tODE(j),stateODE(j,:), ...
                                                                 tStep,Control.rpm,ImpactParams, PropState.rpm, ...
                                                                 Experiment.propCmds);            
                if sum(globalFlag.contact.isContact)>0
                    Contact.hasOccured = 1;
                    if ImpactInfo.firstImpactOccured == 0
                        ImpactInfo.firstImpactOccured = 1;
                    end
                end     
                ContHist = updateconthist(ContHist,stateDeriv, Pose, Twist, Control, PropState, Contact, globalFlag, Sensor); 
            end

            ContHist.times = [ContHist.times;tODE];
            ContHist.states = [ContHist.states,stateODE'];    
        end
        localFlag.contact = globalFlag.contact;     
        state = stateODE(end,:)';
        t = tODE(end);
        [Pose, Twist] = updatekinematics(state, stateDeriv);
        %Discrete Time recording @ 200 Hz
        Hist = updatehist(Hist, t, state, stateDeriv, Pose, Twist, Control, PropState, Contact, localFlag, Sensor);
 
    end
    %%
    Monte = updatemontecarlo(k, IC, Hist, Monte, FuzzyInfo, ImpactInfo, xVelocity);
end
toc
%%
% Cut off the dummy first trial
Monte.trial = Monte.trial(2:end);
Monte.IC = Monte.IC(2:end);
Monte.impactOccured = Monte.impactOccured(2:end);
Monte.impactDetected = Monte.impactDetected(2:end);
Monte.recovery = Monte.recovery(2:end,:);
Monte.xVelocity = Monte.xVelocity(2:end);
Monte.heightLoss = Monte.heightLoss(2:end,:);
Monte.horizLoss = Monte.horizLoss(2:end,:);
Monte.fuzzyInput = Monte.fuzzyInput(2:end,:);
Monte.fuzzyOutput = Monte.fuzzyOutput(2:end);
Monte.accelRef = Monte.accelRef(2:end,:);
Monte.finalHorizVel = Monte.finalHorizVel(2:end);
Monte.failedDetections = sum(Monte.impactOccured) - sum(Monte.impactDetected);
%% Convert to plottable info
Plot = monte2plot(Monte);
  
%% Generate plottable arrays
Plot = hist2plot(Hist);
close all
animate(0,Hist,'ZX',ImpactParams,timeImpact)
