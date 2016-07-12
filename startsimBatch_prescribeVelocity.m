% function [Hist, Plot,ImpactParams, endTimeImpact, accelMagMax,accelMagHorizMax,accelDir_atPeak,angVels_atPeak,angVels_avg] = startsimBatch_prescribeVelocity(VxImpact,pitchImpact)
function [Hist, Plot,ImpactParams,endTimeImpact] = startsimBatch_prescribeVelocity(VxImpact,pitchImpact,yawImpact)

tic

global m g Kt 
global timeImpact
global globalFlag

%% Initialize Simulation Parameters
ImpactParams = initparams_navi;

SimParams.recordContTime = 0;
SimParams.useFaesslerRecovery = 0;%Use Faessler recovery
SimParams.useRecovery = 0; 
SimParams.timeFinal = 2;
tStep = 1/200;%1/200;

ImpactParams.wallLoc = 0.5;%1.5;
ImpactParams.wallPlane = 'YZ';
ImpactParams.timeDes = 0.5;
ImpactParams.frictionModel.muSliding = 0.1;
ImpactParams.frictionModel.velocitySliding = 1e-4; %m/s
timeImpact = 10000;

%% Initialize Structures
IC = initIC;
Control = initcontrol;
PropState = initpropstate;
Setpoint = initsetpoint;

[Contact, ImpactInfo] = initcontactstructs;
localFlag = initflags;

%% Set initial Conditions


%%%--- original way of prescribing velocity
% Control.twist.posnDeriv(1) = VxImpact; %World X Velocity at impact
% IC.attEuler = [deg2rad(0);deg2rad(pitchImpact);deg2rad(yawImpact)];
% IC.posn = [0;0;1];
% Setpoint.posn(3) = IC.posn(3);
% xAcc = 0;
% 
% rotMat = quat2rotmat(angle2quat(-(IC.attEuler(1)+pi),IC.attEuler(2),IC.attEuler(3),'xyz')');
% 
% [IC.posn(1), initialLinVel, SimParams.timeInit, xAcc ] = getinitworldx( ImpactParams, Control.twist.posnDeriv(1),IC, xAcc);
%%%%% - end original way

Control.twist.posnDeriv(1) = VxImpact; %World X Velocity at impact
IC.attEuler = [deg2rad(0);deg2rad(pitchImpact);deg2rad(yawImpact)];
IC.posn = [ImpactParams.wallLoc-0.3;0;1];
Setpoint.posn(3) = IC.posn(3);
xAcc = 0;

rotMat = quat2rotmat(angle2quat(-(IC.attEuler(1)+pi),IC.attEuler(2),IC.attEuler(3),'xyz')');

SimParams.timeInit = 0;
Setpoint.head = IC.attEuler(3);
Setpoint.time = SimParams.timeInit;
Setpoint.posn(1) = IC.posn(1);
Trajectory = Setpoint;

IC.linVel =  rotMat*[VxImpact;0;0];

Experiment.propCmds = [];
Experiment.manualCmds = [];

globalFlag.experiment.rpmChkpt = zeros(4,1);
globalFlag.experiment.rpmChkptIsPassed = zeros(1,4);

[IC.rpm, Control.u] = initrpm(rotMat, [xAcc;0;0]); %Start with hovering RPM


PropState.rpm = IC.rpm;

%% Initialize state and kinematics structs from ICs
[state, stateDeriv] = initstate(IC, xAcc);
[Pose, Twist] = updatekinematics(state, stateDeriv);

%% Initialize sensors
Sensor = initsensor(rotMat, stateDeriv, Twist);

%% Initialize History Arrays

% Initialize history 
Hist = inithist(SimParams.timeInit, state, stateDeriv, Pose, Twist, Control, PropState, Contact, localFlag, Sensor);

% Initialize Continuous History
if SimParams.recordContTime == 1 
    ContHist = initconthist(SimParams.timeInit, state, stateDeriv, Pose, Twist, Control, ...
                            PropState, Contact, globalFlag, Sensor);
end


%% Simulation Loop
for iSim = SimParams.timeInit:tStep:SimParams.timeFinal-tStep
%     display(iSim)    
   
    %% Sensors
    rotMat = quat2rotmat(Pose.attQuat);
    Sensor.accelerometer = (rotMat*[0;0;g] + stateDeriv(1:3) + cross(Twist.angVel,Twist.linVel))/g; %in g's
    Sensor.gyro = Twist.angVel;
  
    %% Control
    if ImpactInfo.firstImpactOccured*SimParams.useRecovery == 1 %recovery control        
        if SimParams.useFaesslerRecovery == 1        
            recoveryStage = checkrecoverystage(Pose, Twist) ;

            Control = computedesiredacceleration(Control, Pose, Twist, recoveryStage);    
            % Compute control outputs
            Control = controllerrecovery(tStep, Pose, Twist, Control);   
            Control.type = 'recovery';
        else
            Control.pose.posn = [0;0;2];
            Control = controllerposn(state,iSim,SimParams.timeInit,tStep,Trajectory(end).head,Control);
            
            Control.type = 'posn';
            
%             Control = controlleratt(state,iSim,SimParams.timeInit,tStep,2,[0;deg2rad(20);0],Control,timeImpact, manualCmds)
        end
    else %normal posn control
        recoveryStage = 0;
        Control.desEuler = IC.attEuler;
        Control.pose.posn(3) = Trajectory(end).posn(3);
        Control = controlleratt(state,iSim,SimParams.timeInit,tStep,Control,[]);
        Control.type = 'att';
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
    Hist = updatehist(Hist, t, state, stateDeriv, Pose, Twist, Control, PropState, Contact, localFlag, Sensor);

    %End loop if Spiri has crashed
    if state(9) <= 0
        display('Navi has hit the floor :(');
        ImpactInfo.isStable = 0;
        break;
    end  
    
    if state(7) <= -10
        display('Navi has left the building');
        ImpactInfo.isStable = 1;
        break;
    end
end

toc

% % Get impact info
% if SimParams.recordContTime == 0
%     for iBumper = 1:4
%         ImpactInfo.bumperInfos(iBumper) = getsiminfo(Hist,iBumper, Trajectory(1).head);
%     end
% else
%     for iBumper = 1:4
%         ImpactInfo.bumperInfos(iBumper) = getsiminfo(ContHist,iBumper,Trajectory(1).head);
%     end
% end
% 
% cellBumperInfos = struct2cell(ImpactInfo.bumperInfos);
% 
% ImpactInfo.maxNormalForce = max([cellBumperInfos{find(strcmp(fieldnames(ImpactInfo.bumperInfos),'maxNormalForces')),:}]);
% ImpactInfo.maxDefl = max([cellBumperInfos{find(strcmp(fieldnames(ImpactInfo.bumperInfos),'maxDefls')),:}]);
% ImpactInfo.numContacts = sum([cellBumperInfos{find(strcmp(fieldnames(ImpactInfo.bumperInfos),'numContacts')),:}]);

Plot = hist2plot(Hist);

% For batch output
% accelMagHoriz = colnorm(Plot.accelerometers(1:2,:));
% accelMag = colnorm(Plot.accelerometers);
% % [pks,locs] = findpeaks(accelMagHoriz(vlookup(Plot.times,timeImpact):end),'MINPEAKHEIGHT',0.5,'NPEAKS',1);
% accelPeakLoc = vlookup(Plot.times,timeImpact) + locs - 1;
% accelMagMax = accelMag(accelPeakLoc);
% accelMagHorizMax = pks;
% accelDir_atPeak = Plot.accelerometers(:,accelPeakLoc);
% angVels_atPeak = Plot.angVels(:,accelPeakLoc);
% angVels_avg = mean(Plot.angVels(:,vlookup(Plot.times,timeImpact):accelPeakLoc),2);
endTimeImpact = timeImpact;

end
