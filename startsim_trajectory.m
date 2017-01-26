
% clearvars -except SPKF ASPKF rmse loop_no timer Setpoint Trajectory gamma

global g mag
global timeImpact
global globalFlag

useExpData = 0;

%% Initialize Fuzzy Logic Process
[FuzzyInfo, PREIMPACT_ATT_CALCSTEPFWD] = initfuzzyinput();

%% Initialize Simulation Parameters
ImpactParams = initparams_navi;

SimParams.recordContTime = 0;
SimParams.useFaesslerRecovery = 1;%Use Faessler recovery
SimParams.useRecovery = 1; 
SimParams.timeFinal = 25;
tStep = 1/100;%1/200;

ImpactParams.wallLoc = 0.5;%1.5;
ImpactParams.wallPlane = 'YZ';
ImpactParams.timeDes = 0.5; %Desired time of impact. Does nothing
ImpactParams.frictionModel.muSliding = 0.3;
ImpactParams.frictionModel.velocitySliding = 1e-4; %m/s
timeImpact = 10000;
timeStabilized = 10000;

%% Initialize Structures
IC = initIC;
Control = initcontrol;
PropState = initpropstate;
% Setpoint = initsetpoint;


move_avg_acc = zeros(3,6);


[Contact, ImpactInfo] = initcontactstructs;
localFlag = initflags;

ImpactIdentification = initimpactidentification;

%% Set initial Conditions
IC.posn = [ImpactParams.wallLoc-1.1;0;0.1]; 

Trajectory(1).posn = IC.posn;

IC.angVel = [0;0;0];
IC.attEuler = [0;0;angle_head];
IC.linVel = [0;0;0];
SimParams.timeInit = 0;
rotMat = quat2rotmat(angle2quat(-(IC.attEuler(1)+pi),IC.attEuler(2),IC.attEuler(3),'xyz')');

Experiment.propCmds = [];
Experiment.manualCmds = [];

globalFlag.experiment.rpmChkpt = zeros(4,1);
globalFlag.experiment.rpmChkptIsPassed = zeros(1,4);

[IC.rpm, Control.u] = initrpm(rotMat, [0;0;0]); %Start with hovering RPM

PropState.rpm = IC.rpm;

%% Waypoint Trajectory
% Setpt 1
% Setpoint.head = pi/5;
% Setpoint.time = 4;
% Setpoint.posn = [0;0;5];
% Trajectory = Setpoint;
% 
% % Setpt 2
% Setpoint.head = pi/5;
% Setpoint.time = Setpoint.time + 10;
% Setpoint.posn = [8;0;5];
% Trajectory = [Trajectory;Setpoint];

% % Setpt 3
% Setpoint.head = 0;
% Setpoint.time = Setpoint.time + 5;
% Setpoint.posn = [1;1;2];
% Trajectory = [Trajectory;Setpoint];
% 
% % Setpt 4
% Setpoint.head = 0;
% Setpoint.time = Setpoint.time + 5;
% Setpoint.posn = [0;1;2];
Trajectory = [Trajectory;Setpoint];
% 
% % Setpt 5
% Setpoint.head = 0;
% Setpoint.time = Setpoint.time + 5;
% Setpoint.posn = [0;0;2];
% Trajectory = [Trajectory;Setpoint];

iTrajectory = 1;

%% Initialize state and kinematics structs from ICs
[state, stateDeriv] = initstate(IC, 0);
[Pose, Twist] = updatekinematics(state, stateDeriv);

%% Initialize sensors
sensParams = initsensor_params(useExpData); % initialize sensor parameters for use in measurement model

Sensor = initsensor(state, stateDeriv, sensParams); % init sensor values
sensParams = initgps_baro(Sensor, sensParams); %init initial GPS and baro in order to initialize cartesian coord at starting spot

Est_sensParams = initEst_sensPars(sensParams); %initialize sensor parameters for use in estimators (to add error, etc.)

%% Initialize state estimators
Est_ICs = initSE_ICs(IC, sensParams, loop_no, useExpData); % set initial condition estimate in order to add errors

EKF = initEKF(Est_ICs);
AEKF = initAEKF(Est_ICs);

SPKF = initSPKF(Est_ICs, loop_no);
ASPKF = initASPKF(Est_ICs);
ASPKF_opt = initASPKF_opt(Est_ICs);

SPKF_noN = initSPKF(Est_ICs, loop_no);
ASPKF_noN = initASPKF(Est_ICs);
ASPKF_opt_noN = initASPKF_opt(Est_ICs);

SRSPKF = initSRSPKF(Est_ICs);

COMP = initCOMP(Est_ICs);

EKF_att = initEKF_att(Est_ICs, loop_no);
HINF = initHINF(Est_ICs);
AHINF = initAHINF(Est_ICs);

EKF_att_noN = initEKF_att(Est_ICs, loop_no);
HINF_noN = initHINF(Est_ICs);
AHINF_noN = initAHINF(Est_ICs);

SRSPKF_full = initSRSPKF_full(Est_ICs);

SPKF_full = initSPKF_full(Est_ICs, loop_no);
SPKF_norm = initSPKF_norm(Est_ICs, loop_no);



time_to_break = 0; %var so sim doesn't stop once it's stabilized
%% Initialize History Arrays

% Initialize history 
Hist = inithist(SimParams.timeInit, state, stateDeriv, Pose, Twist, Control, PropState, Contact, localFlag, Sensor, ...
                sensParams, EKF, AEKF, SPKF, ASPKF, COMP, HINF, SPKF_full,EKF_att,SRSPKF, SRSPKF_full, ASPKF_opt, AHINF, ...
                SPKF_norm, useExpData, SPKF_noN, ASPKF_noN, ASPKF_opt_noN, EKF_att_noN, HINF_noN, AHINF_noN);
            
% Initialize Continuous History
if SimParams.recordContTime == 1 
    ContHist = initconthist(SimParams.timeInit, state, stateDeriv, Pose, Twist, Control, ...
                            PropState, Contact, globalFlag, Sensor);
end

%% Simulation Loop
for iSim = SimParams.timeInit:tStep:SimParams.timeFinal-tStep
%     display(iSim)    
    %% Loop through waypoints
    if iSim > Trajectory(iTrajectory).time
        if iTrajectory + 1 <= numel(Trajectory)
            iTrajectory = iTrajectory + 1;            
        end
    end  

    
    %% Impact Detection    
    [ImpactInfo, ImpactIdentification] = detectimpact(iSim, ImpactInfo, ImpactIdentification,...
                                                      Sensor,Hist.poses,PREIMPACT_ATT_CALCSTEPFWD);
    [FuzzyInfo] = fuzzylogicprocess(iSim, ImpactInfo, ImpactIdentification,...
                                    Sensor, Hist.poses(end), SimParams, Control, FuzzyInfo);
                                
    % Calculate accelref in world frame based on FuzzyInfo.output, estWallNormal
    if sum(FuzzyInfo.InputsCalculated) == 4 && Control.accelRefCalculated == 0;
            disp(FuzzyInfo.output);
            Control.accelRef = calculaterefacceleration(FuzzyInfo.output, ImpactIdentification.wallNormalWorld);
            disp(Control.accelRef);
            Control.accelRefCalculated = 1;
    end
    
    %% Control
    if Control.accelRefCalculated*SimParams.useRecovery == 1 %recovery control       
        if SimParams.useFaesslerRecovery == 1  
            
            Control = checkrecoverystage(Pose, Twist, Control, ImpactInfo);
            [Control] = computedesiredacceleration(Control, Twist);

            % Compute control outputs
            [Control] = controllerrecovery(tStep, Pose, Twist, Control);       
            Control.type = 'recovery';
            
        else %Setpoint recovery
            disp('Setpoint recovery');
            Control.pose.posn = [0;0;2];
            Control = controllerposn(state,iSim,SimParams.timeInit,tStep,Trajectory(end).head,Control);
            
            Control.type = 'posn';
            
%             Control = controlleratt(state,iSim,SimParams.timeInit,tStep,2,[0;deg2rad(20);0],Control,timeImpact, manualCmds)
        end
    else %normal posn control
        Control.pose.posn = Trajectory(iTrajectory).posn;
        Control.recoveryStage = 0;
        Control = controllerposn(state,iSim,SimParams.timeInit,tStep,Trajectory(end).head,Control);
        
        Control.type = 'posn';
    end
    
    
    %% Propagate Dynamics
    options = getOdeOptions();
    [tODE,stateODE] = ode45(@(tODE, stateODE) dynamicsystem(tODE,stateODE, ...
                                                            tStep,Control.rpm,ImpactParams,PropState.rpm, ...
                                                            Experiment.propCmds),[iSim iSim+tStep],state,options);
    
    % Reset contact flags for continuous time recording        
    globalFlag.contact = localFlag.contact;
    
        
    [stateDeriv, Contact, PropState] = dynamicsystem(tODE(end),stateODE(end,:), ...
                                                     tStep,Control.rpm,ImpactParams, PropState.rpm, ...
                                                     Experiment.propCmds);  
    
     %% Update Sensors
    [Sensor,sensParams] = measurement_model(state, stateDeriv, sensParams, tStep);
    
%     [Sensor.acc, move_avg_acc] = moving_avg_filt(Sensor.acc, move_avg_acc);
    %% State Estimation
    tic;
    SPKF = SPKF_attitude(Sensor, SPKF, EKF, Est_sensParams, tStep);
    timer(1) = timer(1) + toc;
    
% %     
    tic;
    ASPKF = ASPKF_attitude(Sensor, ASPKF, EKF, Est_sensParams, tStep);
    timer(2) = timer(2) + toc;
%     
    tic;
    EKF_att = EKF_attitude(Sensor, EKF_att, EKF, Est_sensParams, tStep);
    timer(3) = timer(3) + toc;
    
%     tic;
%     SPKF_full = SPKF_full_state(Sensor, SPKF_full, Est_sensParams, tStep, iSim);
%     timer(4) = timer(4) + toc;
% % % % %     
    tic;
    COMP = CompFilt_attitude(Sensor, COMP, EKF, Est_sensParams, tStep);
    timer(5) = timer(5) + toc;
% % %     
    tic;
    HINF = HINF_attitude(Sensor, HINF, EKF, Est_sensParams, tStep);
    timer(6) = timer(6) + toc;
%     
    tic;
    SRSPKF = SRSPKF_attitude(Sensor, SRSPKF, EKF, Est_sensParams, tStep);
    timer(7) = timer(7) + toc;
%     
%     tic;
%     SRSPKF_full = SRSPKF_full_state(Sensor, SRSPKF_full, Est_sensParams, tStep, iSim);
%     timer(8) = timer(8) + toc;
%     
    tic;
    ASPKF_opt = ASPKF_opt_attitude(Sensor, ASPKF_opt, EKF, Est_sensParams, tStep);
    timer(9) = timer(9) + toc;
% %     
    tic;
    AHINF = AHINF_attitude(Sensor, AHINF, EKF, Est_sensParams, tStep);
    timer(10) = timer(10) + toc;
% 
%     tic;
%     SPKF_norm = SPKF_norm_const(Sensor, SPKF_norm, EKF, Est_sensParams, tStep);
%     timer(11) = timer(11) + toc;
    
    tic;
    SPKF_noN = SPKF_attitude_noN(Sensor, SPKF_noN, EKF, Est_sensParams, tStep);
    timer(12) = timer(12) + toc;
    
    tic;
    ASPKF_noN = ASPKF_attitude_noN(Sensor, ASPKF_noN, EKF, Est_sensParams, tStep);
    timer(13) = timer(13) + toc;
    
    tic;
    ASPKF_opt_noN = ASPKF_opt_attitude_noN(Sensor, ASPKF_opt_noN, EKF, Est_sensParams, tStep);
    timer(14) = timer(14) + toc;
    
    tic;
    EKF_att_noN = EKF_attitude_noN(Sensor, EKF_att_noN, EKF, Est_sensParams, tStep);
    timer(15) = timer(15) + toc;
%     
    tic;
    HINF_noN = HINF_attitude_noN(Sensor, HINF_noN, EKF, Est_sensParams, tStep);
    timer(16) = timer(16) + toc;
%     
    tic;
    AHINF_noN = AHINF_attitude_noN(Sensor, AHINF_noN, EKF, Est_sensParams, tStep);
    timer(17) = timer(17) + toc;

    
    
% %     
% 
%     EKF = EKF_position(Sensor, EKF, SPKF, Hist.SPKF(end).X_hat.q_hat, Est_sensParams, tStep, iSim);
    
%     AEKF = AEKF_position(Sensor, AEKF, ASPKF, Hist.ASPKF(end).X_hat.q_hat, Est_sensParams, tStep, iSim);
    

    
    
    
    %% Record History
    if SimParams.recordContTime == 0
        
        %moved this up a notch. otherwise the sensors were behind a
        %timestep
%         [stateDeriv, Contact, PropState] = dynamicsystem(tODE(end),stateODE(end,:), ...
%                                                          tStep,Control.rpm,ImpactParams, PropState.rpm, ...
%                                                          Experiment.propCmds);        
        if sum(globalFlag.contact.isContact)>0
            Contact.hasOccured = 1;
            if sensParams.crash.new == 1
                sensParams.crash.time_since = 0;
                sensParams.crash.new = 0;
            end
                
            sensParams.crash.occur = 1;
            
            if ImpactInfo.firstImpactOccured == 0
                ImpactInfo.firstImpactOccured = 1;
            end
        else
            sensParams.crash.new = 1;
        end

    else      
        % Continuous time recording
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
    Hist = updatehist(Hist, t, state, stateDeriv, Pose, Twist, Control, PropState, Contact, localFlag, Sensor, ...
                        sensParams, EKF, AEKF, SPKF, ASPKF, COMP, HINF, SPKF_full,EKF_att, SRSPKF, SRSPKF_full, ASPKF_opt, ...
                        AHINF,SPKF_norm, useExpData, SPKF_noN, ASPKF_noN, ASPKF_opt_noN, EKF_att_noN, HINF_noN, AHINF_noN);
                    
    %% End loop conditions
    % Navi has crashed:
    if state(9) <= 0
        display('Navi has hit the floor :(');
        ImpactInfo.isStable = 0;
        break;
    end  
    
    % Navi has drifted very far away from wall:
    if state(7) <= -30
        display('Navi has left the building');
        ImpactInfo.isStable = 1;
        break;
    end
    
    % Recovery control has worked, altitude stabilized:
    if Control.recoveryStage == 4 && time_to_break == 0
        time_of_recovery = iSim;
        time_to_break = iSim + 10;
    elseif iSim == time_to_break && iSim ~= 0
        display('Altitude has been stabilized');
        ImpactInfo.isStable = 1;
        break;
    end
end

toc

%% Generate plottable arrays
Plot = hist2plot(Hist, useExpData);


font_size = 15;
line_size = 15;
line_width = 2;

