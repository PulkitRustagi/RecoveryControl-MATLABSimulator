function Monte = updatemontecarlo(k, IC, Hist, Monte)
    Monte.trial = [Monte.trial; k];
    Monte.IC = [Monte.IC; IC];
    
    % check if and when it does impact and recover
    impactIndex = 0;
    recoveryIndex = 0;
    
    % process recovery parameters 
    recovered = [0 0 0 0];
    for i = 1:length(Hist.times)
        switch Hist.controls(i).recoveryStage
            case 0
            case 1
                if Hist.controls(i-1).recoveryStage == 0
                    recovered(1) = Hist.times(i);
                    impactIndex = i;
                end
            case 2
                if Hist.controls(i-1).recoveryStage < 2
                    recovered(2) = Hist.times(i);
                end
            case 3
                if Hist.controls(i-1).recoveryStage < 3
                    recovered(3) = Hist.times(i);
                end
            case 4
                if Hist.controls(i-1).recoveryStage < 4
                    recovered(4) = Hist.times(i);
                    recoveryIndex = i;
                end
            otherwise 
                error('Monte Carlo recovery times failed');
        end  
    end
    % later check if a recovery time was zero, this is a failed recovery 
    Monte.recovery = [Monte.recovery; recovered];
    
    if impactIndex > 0 && recoveryIndex > 0
        Monte.heightLoss = [Monte.heightLoss; Hist.poses(recoveryIndex).posn(3) - Hist.poses(impactIndex).posn(3)];
        Monte.horizLoss = [Monte.horizLoss; ...
            abs(sqrt( (Hist.poses(recoveryIndex).posn(1)-Hist.poses(impactIndex).posn(1))^2 + ...
                      (Hist.poses(recoveryIndex).posn(2)-Hist.poses(impactIndex).posn(2))^2))];
    else
        Monte.heightLoss = [Monte.heightLoss; 0];
        Monte.horizLoss = [Monte.horizLoss; 0];
    end
end