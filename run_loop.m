% loop to test variables
clearvars;

timer = zeros(10,1);

angle_head = 1;
posn_hit = 0;

for loop_no = 5:5
  
    clearvars -except loop_no timer rmse angle_head posn_hit
    
    if mod(loop_no-1,5) == 0
        angle_head = 1;
        posn_hit = posn_hit+5;
    end
    
    
    % set waypoints for run. 
    Setpoint = initsetpoint;
    
    
    % Setpt 1
    Setpoint.head = angle_head*pi/5;
    Setpoint.time = 4;
    Setpoint.posn = [0;0;5];
    Trajectory = Setpoint;
    
    % Setpt 2
    Setpoint.head = angle_head*pi/5;
    Setpoint.time = Setpoint.time + 10;
    Setpoint.posn = [posn_hit;0;5];
    Trajectory = [Trajectory;Setpoint];
    
    
    startsim_trajectory;
    
  
    if ~exist('time_of_recovery','var');
        time_of_recovery = iSim;
    end
    rmse(loop_no,:) = rmse_att(Plot,sensParams,time_of_recovery/tStep);
    
    
    
    if mod(loop_no,2) == 0
    
%     plot_SE;
    end

    
    angle_head = angle_head + 1;


    
end

PlotRMSE = RMSE_to_plot(rmse);

