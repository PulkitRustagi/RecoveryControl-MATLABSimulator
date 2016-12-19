function Plot = monte2plot(Monte)
    Plot.trial = Monte.trial;
    % ICs
    temp = struct2cell(Monte.IC);
    % positions
    Plot.initPositions = [temp{1,:}];
    % body rates
    Plot.initBodyrates = [temp{2,:}];
    % incoming angles
    Plot.initAngles = [temp{3,:}];
    % speed
    Plot.initSpeeds = [temp{4,:}];   
   
    num_iter = Monte.trial(end);
    % Extract number of trials that recovered 
    Plot.fractionReachedStageOne   = sum(Monte.recovery(:,1) > 0)/num_iter;
    Plot.fractionReachedStageTwo   = sum(Monte.recovery(:,2) > 0)/num_iter;
    Plot.fractionReachedStageThree = sum(Monte.recovery(:,3) > 0)/num_iter;
    Plot.fractionReachedStageFour  = sum(Monte.recovery(:,4) > 0)/num_iter;
 
    % get spectrum of recovery times
    Plot.timeUntilStageTwo   = Monte.recovery(:,2);
    Plot.timeUntilStageThree = Monte.recovery(:,3);
    Plot.timeUntilStageFour = Monte.recovery(:,4);

 
    Plot.heightLoss = Monte.heightLoss;
    Plot.horizLoss = Monte.horizLoss;
    
    no_crash = Plot.trial(Monte.recovery(:,1)==0);
    no_recover = Plot.trial(Plot.timeUntilStageTwo==0);
    Plot.failure = no_recover(ismember(no_recover,no_crash)==0);

end