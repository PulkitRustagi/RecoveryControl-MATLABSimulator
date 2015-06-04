clear all;
% close all;
clc;

global CM prop_loc m

%%Spiri System Parameters
InitSpiriParams;
r_ribbon = 0.31;

%%Simulation Parameters
traj_posn = [0 2.5 -5;5 2.5 -5];
traj_head = [0;0];
traj_time = [0;6];
t0 = traj_time(1);
tf = traj_time(end);
dt = 1/30;
% ref_r = [2 2 -5]';
% ref_head = pi/4;
x0 = [zeros(6,1);traj_posn(1,:)';[1;0;0;0];zeros(3,1)];
omega0 = zeros(4,1);

[posn,head] = CreateTrajectory(traj_posn,traj_head,traj_time,dt);

%%Initial Variable Values
x0_step = x0;
Xtotal = x0';
ttotal = t0;
vztotal = [];
ez_prev = 0;
evz_prev = 0;
evx_prev = 0;
evy_prev = 0;
eyaw_prev = 0;
eroll_prev = 0;
epitch_prev = 0;
er_prev = 0;
omega_prev = omega0;

flag_c = 0;
flag_dec = 0;
defl2=0;
Fc2 = 0;

Fc = [];
Pc = [];
traj_index = 1;
index_defl = 1;
numContacts = 0;
defl_contact = 0;
for i = t0:dt:tf-dt
%     display(i)
    %Determine if Contact has occured
    % determine contact pt from middle section of sphere
    % track penetration of contact pt
    
    %Wall @ x = 4m
%     if (4 - Xtotal(end,7)) <= r_ribbon
%         if flag_c == 0 
%             [ pB_contact,pW_wall,vB_normal,vi_contact,ti_contact,numContacts,flag_c ] = DetectContact(i, Xtotal(end,:), r_ribbon, numContacts );
%             flag_c
%             flag_dec = 0;
%         end             
%         
%         if flag_c == 1
%         
%             q = [Xtotal(end,10);Xtotal(end,11);Xtotal(end,12);Xtotal(end,13)];
%             q = q/norm(q);
%             R = quatRotMat(q);
%             T = [Xtotal(end,7);Xtotal(end,8);-Xtotal(end,9)];
% 
%             pW_contact = R'*pB_contact + T;
%             defl_contact = sum((pW_contact - pW_wall).^2);
%             defl(index_defl) = defl_contact;
%             defl_time(index_defl) = i;
%     %         index_defl = index_defl + 1;
%             defl_prev = defl(index_defl-1);
% 
%             if flag_dec == 0
%                 if defl_contact < defl_prev
%                     flag_dec = 1;
%                 end
%             else
%                 if defl_contact > defl_prev
%                       vf_contact = sqrt(sum(Xtotal(end,1:3).^2))
%                       t_contact(numContacts) = i - ti_contact;
%                       flag_c = 0
%                       [ pB_contact,pW_wall,vB_normal,vi_contact,ti_contact,numContacts,flag_c ] = DetectContact( i,Xtotal(end,:), r_ribbon, numContacts );
%                       flag_c
%                       
%                       if flag_c == 1
%                       pW_contact = R'*pB_contact + T;
%                       defl_contact = sum((pW_contact - pW_wall).^2);
%                       defl(index_defl) = defl_contact;
%                       defl_time(index_defl) = i;
%             %         index_defl = index_defl + 1;
%                       defl_prev = defl(index_defl-1);
% 
%                       flag_dec = 0;  
%                       display(strcat('Rebound effect at t = ',num2str(i),' s'));
%                       end
%     %                 display('Spiri has crashed miserably into the wall :(');
%     %                 break;
%                 end
%             end
%         
%        
%              %Find contact Force using Hunt & Crossley's contact model
%             e_ribbon = 0.7;
%             k_ribbon = 5000;%1*10^5; %[N/m]
%             n_ribbon = 1.5;
% 
%             %lambda from Herbert & McWhannell
%             lambda_ribbon = 6*(1-e_ribbon)/(((2*e_ribbon-1)^2+3)*vi_contact);
% 
%             Fc_mag = abs((defl_contact^n_ribbon)*(lambda_ribbon*((defl_contact-defl_prev)/dt) + k_ribbon));
%     %         Fc_mag = 150;
%             %Hertz's Model
%     %         Fc_mag = 30*defl_contact^1.5;
%     %         Fc_mag = 10000*defl_contact^1.5;
%         end
%         
%         if flag_c == 0
%             vB_normal = [];
%             pB_contact = [];
%             defl_contact = 0;  
%             defl_time(index_defl) = i;
%             defl(index_defl) = defl_contact;
%     %         index_defl = index_defl + 1;
%     %         vi_contact = 0;
%     %         defl_prev = 0;
%             Fc_mag = 0;
%             pW_contact = [Xtotal(end,7);Xtotal(end,8);-Xtotal(end,9)];
%          
%         end
%         
%     else
%         vB_normal = [];
%         pB_contact = [];
%         defl_contact = 0;  
%         defl_time(index_defl) = i;
%         defl(index_defl) = defl_contact;
% %         index_defl = index_defl + 1;
% %         vi_contact = 0;
% %         defl_prev = 0;
%         Fc_mag = 0;
%         pW_contact = [Xtotal(end,7);Xtotal(end,8);-Xtotal(end,9)];;
%         if flag_c == 1 
%             vf_contact = sqrt(sum(Xtotal(end,1:3).^2))
%             t_contact(numContacts) = i - ti_contact;
%             flag_c = 0
%         end
%     end
%     Fc(index_defl) = Fc_mag;
%     Pc(:,index_defl) = pW_contact;
%     if flag_c == 1
%     if flag_dec == 0
%         if defl_contact < defl_prev
%             flag_dec = 1;
%         end
%     else
%         if defl_contact > defl_prev
%             display('Spiri has crashed miserably into the wall :(');
%             break;
%         end
%     end
%     end
    
% % Wall @ 4m

    q = [Xtotal(end,10);Xtotal(end,11);Xtotal(end,12);Xtotal(end,13)];
    q = q/norm(q);
    R = quatRotMat(q);
    T = [Xtotal(end,7);Xtotal(end,8);-Xtotal(end,9)];

    if (4 - Xtotal(end,7)) <= r_ribbon
        if flag_c == 0
            [pB_contact,pW_wall,vi_contact,ti_contact,numContacts,flag_c] = Contact_Detect(i, Xtotal(end,:), r_ribbon, numContacts );
            if flag_c == 1
                vi_c(numContacts) = sqrt(sum(Xtotal(end,1:3).^2));
                ti_c(numContacts) = ti_contact;
            end
        end    
    end

    defl_prev = defl_contact;
    if flag_c == 1
%         Contact_CalcDefl():
          pW_contact = R'*pB_contact + T;
          defl_contact = sign(pW_contact(1)-pW_wall(1))*sum((pW_contact - pW_wall).^2);
          
          if defl_contact <= 0
              
              flag_dec = 0;
              flag_c = 0;
              Fc_mag = 0;
              defl_contact = 0;
              t_c(numContacts) = i - ti_contact;
              vf_c(numContacts) = sqrt(sum(Xtotal(end,1:3).^2));
              
          else
              if flag_dec == 0
                  if defl_contact < defl_prev
                      flag_dec = 1;
                  end
              end
              if flag_dec && (defl_contact > defl_prev) %Rebound detected
                  flag_dec = 0;
                  flag_c = 0;
                  t_c(numContacts) = i - ti_contact;
                  vf_c(numContacts) = sqrt(sum(Xtotal(end,1:3).^2));
                  [pB_contact,pW_wall,vi_contact(index_defl),ti_contact,numContacts,flag_c] = Contact_Detect(i, Xtotal(end,:), r_ribbon, numContacts );
                  
                  if flag_c == 0
                      Fc_mag = 0;
                      defl_contact = 0;
                  else
                      disp('Rebound Detected');
                      vi_c(numContacts) = sqrt(sum(Xtotal(end,1:3).^2));
                      ti_c(numContacts) = ti_contact;
                      %Contact_CalcDefl():
                      pW_contact = R'*pB_contact + T;
                      defl_contact = sign(pW_contact(1)-pW_wall(1))*sum((pW_contact - pW_wall).^2);
                      if defl_contact <= 0
                          disp('Code Logic Error, Fiona!');
                      end
                  end
              end
              
              if flag_c == 1
%                   vB_normal = R*[-1;0;0];            
%                   vB_normal = vB_normal/norm(vB_normal);
                  
                  %Hertz's Model
%                   Fc_mag = 400*defl_contact^1.5;                  
              end
          end
    else
        Fc_mag = 0;
        vB_normal = [];
        pB_contact = [];
        defl_contact = 0;  
        pW_contact = T;
        pW_wall = T;
    end
    
    defl(index_defl) = defl_contact;    
    Fc(index_defl) = Fc_mag;
    Pc(:,index_defl) = pW_contact;
    Pc_wall(:,index_defl) = pW_wall;
    index_defl = index_defl + 1;

    %Trajectory Control Position
    ref_r = posn(traj_index,:)';
    ref_head = head(traj_index);
    traj_index = traj_index + 1;
    
    %Find Control Signal based on ref_r, ref_head
    if i ~= t0
        x0_step = X(end,:);
        ez_prev = ez;
        evz_prev = evz;
        evx_prev = evx;
        evy_prev = evy;
        eyaw_prev = eyaw;
        eroll_prev = eroll;
        epitch_prev = epitch;
        er_prev = er;
        omega_prev = omega;
    end
    [signal_c3,ez,evz,evx,evy,eyaw,eroll,epitch,er,omega] = ControllerZhang(Xtotal(end,:),i,t0,dt,ref_r,ref_head,ez_prev,evz_prev,eroll_prev,epitch_prev,er_prev,omega_prev);
    
       
    %Use Control Signal to propagate dynamics
    [t,X] = ode113(@(t, X) SpiriMotion(t,X,signal_c3,flag_c,vB_normal,pB_contact,Fc_mag,pW_wall),[i i+dt],x0_step);
    [dX, defl_contact2, Fc_mag2] = SpiriMotion(t,X(end,:)',signal_c3,flag_c,vB_normal,pB_contact,Fc_mag,pW_wall);
%         disp(defl_contact)
    Xtotal = [Xtotal;X(end,:)];
    ttotal = [ttotal;t(end)];
    defl2 = [defl2;defl_contact2];
    Fc2 = [Fc2;Fc_mag2];
       
   
    if Xtotal(end,9) >= 0
        display('Spiri has hit the floor :(');
        break;
    end  
    
    
end
F_calc = m*(vf_c - vi_c)./t_c;


% Graphs( ttotal,Xtotal,ttotal(1:end-1),defl,Fc );
Graphs( ttotal,Xtotal,ttotal,defl2,Fc2 );


% SpiriVisualization(ttotal,Xtotal);





