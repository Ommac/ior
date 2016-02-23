addpath(genpath('/home/kammo/Repos/Enitor/utils'));
addpath(genpath('/home/kammo/Repos/Enitor/dataset'));
addpath(genpath('/home/kammo/Repos/objrecpipe_mat'));
addpath('utils');
clearAllButBP;
close all;

%% Set experimental results relative directory name

saveResult = 1;

customStr = '';
dt = clock;
dt = fix(dt); 	% Get timestamp
expDir = ['Exp_' , customStr , '_' , mat2str(dt)];

resdir = ['results/' , expDir];
mkdir(resdir);

%% Save current script and loadExp in results
tmp = what;
[ST,I] = dbstack('-completenames');
copyfile([tmp.path ,'/', ST.name , '.m'],[ resdir ,'/', ST.name , '.m'])

%% Experiments setup
run_bat_rlsc_noreb = 1;
run_bat_rlsc_yesreb = 1;
run_bat_rlsc_yesreb2 = 1;
run_inc_rlsc_yesreb = 1;
run_inc_rlsc_yesreb2 = 1;

retrain = 1;
trainPart = 0.8;

dataRoot =  '/home/kammo/Repos/ior/data/caffe_centralcrop_meanimagenet2012/';
trainFolder = 'lunedi22';
% testFolder = 'martedi23';
testFolder = 'lunedi22';

ntr = [];
nte = []; 

% classes = 1:28; % classes to be extracted
% classes = 1:4; % classes to be extracted
classes = 1:4:28; % classes to be extracted
% classes = [1 8]; % classes to be extracted
% classes = 0:9; % classes to be extracted

% Class frequencies for train and test sets
% trainClassFreq = [0.1 0.9];
% trainClassFreq = [ 2/19*ones(1,9) , 1/19];
% trainClassFreq = [ 200*ones(1,9) , 10] / ntr;
% trainClassFreq = [0.1658*ones(1,6) 0.005];
trainClassFreq = [0.1658*ones(1,6) 0.005 ];
% trainClassFreq = [0.3250*ones(1,3) 0.025];
% trainClassFreq = [0.0416*ones(1,24) 0.00125];
% trainClassFreq = [];
testClassFreq = [];

% Parameter selection
numLambdas = 12;
minLambdaExp = -10;
maxLambdaExp = 5;
lrng = logspace(maxLambdaExp , minLambdaExp , numLambdas);

numrep = 20;

results.bat_rlsc_yesreb.testAccBuf = zeros(1,numrep);
results.bat_rlsc_yesreb.testCM = zeros(numrep, numel(classes), numel(classes));
results.bat_rlsc_yesreb.bestValAccBuf = zeros(1,numrep);
results.bat_rlsc_yesreb.valAcc = zeros(numrep,numLambdas);
results.bat_rlsc_yesreb.teAcc = zeros(numrep,numLambdas);
results.bat_rlsc_yesreb2 = results.bat_rlsc_yesreb;
results.bat_rlsc_noreb = results.bat_rlsc_yesreb;
results.inc_rlsc_yesreb = results.bat_rlsc_yesreb;
results.inc_rlsc_yesreb2 = results.bat_rlsc_yesreb;

for k = 1:numrep
    
    clc
    display(['Repetition # ', num2str(k), ' of ' , num2str(numrep)]);
    display(' ');
	progressBar(k,numrep);
    display(' ');
    display(' ');

    %% Load data

%     if ~exist('ds','var')
%         ds = iCubWorld28(ntr , nte, 'plusMinusOne' , 1, 1, 0, {classes , trainClassFreq, testClassFreq, {}, trainFolder, testFolder});
        ds = iCubWorld28(ntr , nte, 'zeroOne' , 1, 1, 0, {classes , trainClassFreq, testClassFreq, {}, trainFolder, testFolder});
%         ds = MNIST(ntr , nte, 'plusMinusOne' , 0, 0, 0, {classes , trainClassFreq, testClassFreq});
%         mix up sampled points
        ds.mixUpTrainIdx;
        ds.mixUpTestIdx;
%     else
%         % mix up sampled points
%         ds.trainIdx = ds.trainIdx(randperm(numel(ds.trainIdx)));
%         ds.testIdx = ds.testIdx(randperm(numel(ds.testIdx)));
%     end
%     

    Xtr = ds.X(ds.trainIdx,:);
    Ytr = ds.Y(ds.trainIdx,:);
    Xte = ds.X(ds.testIdx,:);
    Yte = ds.Y(ds.testIdx,:);
    
    ntr = size(Xtr,1);
    nte = size(Xte,1);
    d = size(Xtr,2);
    t  = size(Ytr,2);
    if t == 1
        t = 2;
        p_c1 = ds.trainClassNum(1) / ntr;
        p_c2 = ds.trainClassNum(2) / ntr;
    else
        p = ds.trainClassNum / ntr;
    end

    % Splitting
    ntr1 = round(ntr*trainPart);
    nval1 = round(ntr*(1-trainPart));
    tr1idx = 1:ntr1;
    val1idx = (1:nval1) + ntr1;
    Xtr1 = Xtr(tr1idx,:);
    Xval1 = Xtr(val1idx,:);
    Ytr1 = Ytr(tr1idx,:);
    Yval1 = Ytr(val1idx,:);
    
    
    %% Batch RLSC, exact rebalancing (sqrt(Gamma))
    % Naive Linear Regularized Least Squares Classifier, 
    % with Tikhonov regularization parameter selection

    if run_bat_rlsc_yesreb == 1    

        % Compute rebalancing matrix Gamma
        Gamma = zeros(ntr1);
        if t > 2
            for i = 1:ntr1
                
                currClassIdx = find(Ytr1(i,:) == 1);
%                 Gamma(i,i) = 1 / p(currClassIdx);


%                 Gamma(i,i) = prod(t  * ds.trainClassFreq([1:currClassIdx-1 , currClassIdx+1:t]));
%                 Gamma(i,i) = prod(t  * p([1:currClassIdx-1 , currClassIdx+1:t]));
                Gamma(i,i) = prod( p([1:currClassIdx-1 , currClassIdx+1:t]));
            end
        else
            for i = 1:ntr1
                if Ytr1(i,:) == 1
                    Gamma(i,i) = 1 - p_c1;
                else
                    Gamma(i,i) = 1 - p_c2;
                end
            end
        end
        
        % Precompute cov mat
%         XtX = Xtr1'*Gamma*Xtr1;
%         XtY = Xtr1'*Gamma*Ytr1;
        XtX = Xtr1'*sqrt(Gamma)*Xtr1;
        XtY = Xtr1'*sqrt(Gamma)*Ytr1;
        
%         G = diag(Gamma)';
%         XtX = Xtr1'* ( Xtr1 .* G(ones(1,d),:)');
%         XtY = Xtr1'* ( Ytr1 .* G(ones(1,t),:)');

        lstar = 0;      % Best lambda
        bestAcc = 0;    % Highest accuracy
        for lidx = 1:numel(lrng)

            l = lrng(lidx);

            % Train on TR1
            w = (XtX + ntr1*l*eye(d)) \ XtY;

            % Predict validation labels
            Yval1pred_raw = Xval1 * w;

            % Compute current validation accuracy
            
            if t > 2
                Yval1pred = ds.scoresToClasses(Yval1pred_raw);
                [currAcc , ~] = weightedAccuracy2( Yval1, Yval1pred , classes);
            else

                CM = confusionmat(Yval1,sign(Yval1pred_raw));
                CM = CM ./ repmat(sum(CM,2),1,2);
                currAcc = trace(CM)/2;                
            end
            results.bat_rlsc_yesreb.valAcc(k,lidx) = currAcc;

            if currAcc > bestAcc
                bestAcc = currAcc;
                lstar = l;
            end

            % Compute current test accuracy
            Ytepred_raw = Xte * w;
            
            if t > 2
                Ytepred = ds.scoresToClasses(Ytepred_raw);
                [currAcc , ~] = weightedAccuracy2( Yte, Ytepred , classes);
            else
                CM = confusionmat(Yte,sign(Ytepred_raw));
                CM = CM ./ repmat(sum(CM,2),1,2);
                currAcc = trace(CM)/2;                
            end
            results.bat_rlsc_yesreb.teAcc(k,lidx) = currAcc;
        end

        % Retrain on full training set with selected model parameters,
        %  if requested

        if retrain == 1

            % Compute rebalancing matrix Gamma
            Gamma1 = zeros(ntr);
            if t > 2
                for i = 1:ntr
                    currClassIdx = find(Ytr(i,:) == 1);
%                     Gamma1(i,i) = 1 / p(currClassIdx);
%                     Gamma1(i,i) = prod(t  * ds.trainClassFreq([1:currClassIdx-1 , currClassIdx+1:t]));
%                     Gamma1(i,i) = prod(t  * p([1:currClassIdx-1 , currClassIdx+1:t]));
                    Gamma1(i,i) = prod( p([1:currClassIdx-1 , currClassIdx+1:t]));
                end
            else
                for i = 1:ntr
                    if Ytr(i,:) == 1
                        Gamma1(i,i) = 1 - p_c1;
                    else
                        Gamma1(i,i) = 1 - p_c2;
                    end
                end
            end
            % Compute cov mat
            XtX = Xtr'*sqrt(Gamma1)*Xtr;
            XtY = Xtr'*sqrt(Gamma1)*Ytr;    
%             G1 = diag(Gamma1)';
%             XtX = Xtr'* ( Xtr .* G1(ones(1,d),:)');
%             XtY = Xtr'* ( Ytr .* G1(ones(1,t),:)');

            % Train on TR
            w = (XtX + ntr*lstar*eye(d)) \ XtY;
        end

        % Test on test set & compute accuracy

        % Predict test labels
        Ytepred_raw = Xte * w;
        
        % Compute current accuracy
            
        if t > 2
            Ytepred = ds.scoresToClasses(Ytepred_raw);
            [currAcc , CM] = weightedAccuracy2( Yte, Ytepred , classes);
        else
            CM = confusionmat(Yte,sign(Ytepred_raw));
            CM = CM ./ repmat(sum(CM,2),1,2);
            currAcc = trace(CM)/2;
        end
        
        results.bat_rlsc_yesreb.ntr = ntr;
        results.bat_rlsc_yesreb.nte = nte;
        results.bat_rlsc_yesreb.testAccBuf(k) = currAcc;
        results.bat_rlsc_yesreb.testCM(k,:,:) = CM;
        results.bat_rlsc_yesreb.bestValAccBuf(k) = bestAcc;

    end
    
    
    %% Batch RLSC, exact rebalancing (Gamma)
    % Naive Linear Regularized Least Squares Classifier, 
    % with Tikhonov regularization parameter selection

    if run_bat_rlsc_yesreb2 == 1    

        % Compute rebalancing matrix Gamma
        Gamma = zeros(ntr1);
        if t > 2
            for i = 1:ntr1
                
                currClassIdx = find(Ytr1(i,:) == 1);
%                 Gamma(i,i) = 1 / p(currClassIdx);


%                 Gamma(i,i) = prod(t  * ds.trainClassFreq([1:currClassIdx-1 , currClassIdx+1:t]));
%                 Gamma(i,i) = prod(t  * p([1:currClassIdx-1 , currClassIdx+1:t]));
                Gamma(i,i) = prod( p([1:currClassIdx-1 , currClassIdx+1:t]));
            end
        else
            for i = 1:ntr1
                if Ytr1(i,:) == 1
                    Gamma(i,i) = 1 - p_c1;
                else
                    Gamma(i,i) = 1 - p_c2;
                end
            end
        end
        
        % Precompute cov mat
%         XtX = Xtr1'*Gamma*Xtr1;
%         XtY = Xtr1'*Gamma*Ytr1;
        XtX = Xtr1'*Gamma*Xtr1;
        XtY = Xtr1'*Gamma*Ytr1;
        
%         G = diag(Gamma)';
%         XtX = Xtr1'* ( Xtr1 .* G(ones(1,d),:)');
%         XtY = Xtr1'* ( Ytr1 .* G(ones(1,t),:)');

        lstar = 0;      % Best lambda
        bestAcc = 0;    % Highest accuracy
        for lidx = 1:numel(lrng)

            l = lrng(lidx);

            % Train on TR1
            w = (XtX + ntr1*l*eye(d)) \ XtY;

            % Predict validation labels
            Yval1pred_raw = Xval1 * w;

            % Compute current validation accuracy
            
            if t > 2
                Yval1pred = ds.scoresToClasses(Yval1pred_raw);
                [currAcc , ~] = weightedAccuracy2( Yval1, Yval1pred , classes);
            else

                CM = confusionmat(Yval1,sign(Yval1pred_raw));
                CM = CM ./ repmat(sum(CM,2),1,2);
                currAcc = trace(CM)/2;                
            end
            results.bat_rlsc_yesreb2.valAcc(k,lidx) = currAcc;

            if currAcc > bestAcc
                bestAcc = currAcc;
                lstar = l;
            end

            % Compute current test accuracy
            Ytepred_raw = Xte * w;
            
            if t > 2
                Ytepred = ds.scoresToClasses(Ytepred_raw);
                [currAcc , ~] = weightedAccuracy2( Yte, Ytepred , classes);
            else
                CM = confusionmat(Yte,sign(Ytepred_raw));
                CM = CM ./ repmat(sum(CM,2),1,2);
                currAcc = trace(CM)/2;                
            end
            results.bat_rlsc_yesreb2.teAcc(k,lidx) = currAcc;
        end

        % Retrain on full training set with selected model parameters,
        %  if requested

        if retrain == 1

            % Compute rebalancing matrix Gamma
            Gamma1 = zeros(ntr);
            if t > 2
                for i = 1:ntr
                    currClassIdx = find(Ytr(i,:) == 1);
%                     Gamma1(i,i) = 1 / p(currClassIdx);
%                     Gamma1(i,i) = prod(t  * ds.trainClassFreq([1:currClassIdx-1 , currClassIdx+1:t]));
%                     Gamma1(i,i) = prod(t  * p([1:currClassIdx-1 , currClassIdx+1:t]));
                    Gamma1(i,i) = prod( p([1:currClassIdx-1 , currClassIdx+1:t]));
                end
            else
                for i = 1:ntr
                    if Ytr(i,:) == 1
                        Gamma1(i,i) = 1 - p_c1;
                    else
                        Gamma1(i,i) = 1 - p_c2;
                    end
                end
            end
            % Compute cov mat
            XtX = Xtr'*Gamma1*Xtr;
            XtY = Xtr'*Gamma1*Ytr;    
%             G1 = diag(Gamma1)';
%             XtX = Xtr'* ( Xtr .* G1(ones(1,d),:)');
%             XtY = Xtr'* ( Ytr .* G1(ones(1,t),:)');

            % Train on TR
            w = (XtX + ntr*lstar*eye(d)) \ XtY;
        end

        % Test on test set & compute accuracy

        % Predict test labels
        Ytepred_raw = Xte * w;
        
        % Compute current accuracy
            
        if t > 2
            Ytepred = ds.scoresToClasses(Ytepred_raw);
            [currAcc , CM] = weightedAccuracy2( Yte, Ytepred , classes);
        else
            CM = confusionmat(Yte,sign(Ytepred_raw));
            CM = CM ./ repmat(sum(CM,2),1,2);
            currAcc = trace(CM)/2;
        end
        
        results.bat_rlsc_yesreb2.ntr = ntr;
        results.bat_rlsc_yesreb2.nte = nte;
        results.bat_rlsc_yesreb2.testAccBuf(k) = currAcc;
        results.bat_rlsc_yesreb2.testCM(k,:,:) = CM;
        results.bat_rlsc_yesreb2.bestValAccBuf(k) = bestAcc;

    end

    
    %% Batch RLSC, no rebalancing
    % Naive Linear Regularized Least Squares Classifier, 
    % with Tikhonov regularization parameter selection

    if run_bat_rlsc_noreb == 1    

        % Precompute cov mat
        XtX = Xtr1'*Xtr1;
        XtY = Xtr1'*Ytr1;

        lstar = 0;      % Best lambda
        bestAcc = 0;    % Highest accuracy
        for lidx = 1:numel(lrng)

            l = lrng(lidx);

            % Train on TR1
            w = (XtX + ntr1*l*eye(d)) \ XtY;

            % Predict validation labels
            Yval1pred_raw = Xval1 * w;

            % Compute current accuracy
            
            if t > 2
                Yval1pred = ds.scoresToClasses(Yval1pred_raw);
                [currAcc , ~] = weightedAccuracy2( Yval1, Yval1pred , classes);
            else
                CM = confusionmat(Yval1,sign(Yval1pred_raw));
                CM = CM ./ repmat(sum(CM,2),1,2);
                currAcc = trace(CM)/2;                
            end
            
            results.bat_rlsc_noreb.valAcc(k,lidx) = currAcc;

            if currAcc > bestAcc
                bestAcc = currAcc;
                lstar = l;
            end
            
            % Compute current test accuracy
            Ytepred_raw = Xte * w;

            if t > 2
                Ytepred = ds.scoresToClasses(Ytepred_raw);
                [currAcc , ~] = weightedAccuracy2( Yte, Ytepred , classes);
            else
                CM = confusionmat(Yte,sign(Ytepred_raw));
                CM = CM ./ repmat(sum(CM,2),1,2);
                currAcc = trace(CM)/2;                
            end
            
            results.bat_rlsc_noreb.teAcc(k,lidx) = currAcc;
        end

        % Retrain on full training set with selected model parameters,
        %  if requested

        if retrain == 1

            % Compute cov mat
            XtX = Xtr'*Xtr;
            XtY = Xtr'*Ytr;    

            % Train on TR
            w = (XtX + ntr*lstar*eye(d)) \ XtY;
        end

        % Test on test set & compute accuracy

        % Predict test labels
        Ytepred_raw = Xte * w;

        % Compute current accuracy

        if t > 2
            Ytepred = ds.scoresToClasses(Ytepred_raw);            
            [currAcc , CM] = weightedAccuracy2( Yte, Ytepred , classes);
        else
            CM = confusionmat(Yte,sign(Ytepred_raw));
            CM = CM ./ repmat(sum(CM,2),1,2);
            currAcc = sum(trace(CM))/2;
        end
        
        results.bat_rlsc_noreb.ntr = ntr;
        results.bat_rlsc_noreb.nte = nte;
        results.bat_rlsc_noreb.testAccBuf(k) = currAcc;
        results.bat_rlsc_noreb.testCM(k,:,:) = CM;
        results.bat_rlsc_noreb.bestValAccBuf(k) = bestAcc;

    end
    
    
    
    %% Incremental RLSC, recoding (sqrt(Gamma))
    % Naive Linear Regularized Least Squares Classifier, 
    % with Tikhonov regularization parameter selection

    if run_inc_rlsc_yesreb == 1

        % Compute rebalancing matrix Gamma
        Gamma = zeros(ntr1);
        if t > 2
            for i = 1:ntr1
                
                currClassIdx = find(Ytr1(i,:) == 1);
%                 Gamma(i,i) = 1 / p(currClassIdx);


%                 Gamma(i,i) = prod(t  * ds.trainClassFreq([1:currClassIdx-1 , currClassIdx+1:t]));
%                 Gamma(i,i) = prod(t  * p([1:currClassIdx-1 , currClassIdx+1:t]));
                Gamma(i,i) = prod( p([1:currClassIdx-1 , currClassIdx+1:t]));
            end
        else
            for i = 1:ntr1
                if Ytr1(i,:) == 1
                    Gamma(i,i) = 1 - p_c1;
                else
                    Gamma(i,i) = 1 - p_c2;
                end
            end
        end
        
        % Precompute cov mat
        XtX = Xtr1'*Xtr1;
        XtY = Xtr1'*sqrt(Gamma)*Ytr1;
%         G = diag(Gamma)';
%         XtY = Xtr1'* ( Ytr1 .* G(ones(1,t),:)');
%         XtY = Xtr1'* ( Ytr1 .* sqrt(G(ones(1,t),:))');

        lstar = 0;      % Best lambda
        bestAcc = 0;    % Highest accuracy
        for lidx = 1:numel(lrng)

            l = lrng(lidx);

            % Train on TR1
            w = (XtX + ntr1*l*eye(d)) \ XtY;

            % Predict validation labels
            Yval1pred_raw = Xval1 * w;

            % Compute current validation accuracy
            
            if t > 2
                Yval1pred = ds.scoresToClasses(Yval1pred_raw);
                [currAcc , ~] = weightedAccuracy2( Yval1, Yval1pred , classes);
            else

                CM = confusionmat(Yval1,sign(Yval1pred_raw));
                CM = CM ./ repmat(sum(CM,2),1,2);
                currAcc = trace(CM)/2;                
            end
            results.inc_rlsc_yesreb.valAcc(k,lidx) = currAcc;

            if currAcc > bestAcc
                bestAcc = currAcc;
                lstar = l;
            end

            % Compute current test accuracy
            Ytepred_raw = Xte * w;
            
            if t > 2
                Ytepred = ds.scoresToClasses(Ytepred_raw);
                [currAcc , ~] = weightedAccuracy2( Yte, Ytepred , classes);
            else
                CM = confusionmat(Yte,sign(Ytepred_raw));
                CM = CM ./ repmat(sum(CM,2),1,2);
                currAcc = trace(CM)/2;                
            end
            results.inc_rlsc_yesreb.teAcc(k,lidx) = currAcc;
        end

        % Retrain on full training set with selected model parameters,
        %  if requested

        if retrain == 1

            % Compute rebalancing matrix Gamma
            Gamma1 = zeros(ntr);
            if t > 2
                for i = 1:ntr
                    currClassIdx = find(Ytr(i,:) == 1);
%                     Gamma1(i,i) = 1 / p(currClassIdx);
%                     Gamma1(i,i) = prod(t  * ds.trainClassFreq([1:currClassIdx-1 , currClassIdx+1:t]));
%                     Gamma1(i,i) = prod(t  * p([1:currClassIdx-1 , currClassIdx+1:t]));
                    Gamma1(i,i) = prod( p([1:currClassIdx-1 , currClassIdx+1:t]));
                end
            else
                for i = 1:ntr
                    if Ytr(i,:) == 1
                        Gamma1(i,i) = 1 - p_c1;
                    else
                        Gamma1(i,i) = 1 - p_c2;
                    end
                end
            end
            % Compute cov mat
            XtX = Xtr'*Xtr;
            XtY = Xtr'*sqrt(Gamma1)*Ytr;    
%             G1 = diag(Gamma1)';
%             XtY = Xtr'* ( Ytr .* G1(ones(1,t),:)');
%             XtY = Xtr'* ( Ytr .* sqrt(G1(ones(1,t),:))');

            % Train on TR
            w = (XtX + ntr*lstar*eye(d)) \ XtY;
        end

        % Test on test set & compute accuracy

        % Predict test labels
        Ytepred_raw = Xte * w;
        
        % Compute current accuracy
            
        if t > 2
            Ytepred = ds.scoresToClasses(Ytepred_raw);
            [currAcc , CM] = weightedAccuracy2( Yte, Ytepred , classes);
        else
            CM = confusionmat(Yte,sign(Ytepred_raw));
            CM = CM ./ repmat(sum(CM,2),1,2);
            currAcc = trace(CM)/2;
        end
        
        results.inc_rlsc_yesreb.ntr = ntr;
        results.inc_rlsc_yesreb.nte = nte;
        results.inc_rlsc_yesreb.testAccBuf(k) = currAcc;
        results.inc_rlsc_yesreb.testCM(k,:,:) = CM;
        results.inc_rlsc_yesreb.bestValAccBuf(k) = bestAcc;

    end
    
    
    %% Incremental RLSC, recoding (Gamma)
    % Naive Linear Regularized Least Squares Classifier, 
    % with Tikhonov regularization parameter selection

    if run_inc_rlsc_yesreb2 == 1

        % Compute rebalancing matrix Gamma
        Gamma = zeros(ntr1);
        if t > 2
            for i = 1:ntr1
                
                currClassIdx = find(Ytr1(i,:) == 1);
%                 Gamma(i,i) = 1 / p(currClassIdx);


%                 Gamma(i,i) = prod(t  * ds.trainClassFreq([1:currClassIdx-1 , currClassIdx+1:t]));
%                 Gamma(i,i) = prod(t  * p([1:currClassIdx-1 , currClassIdx+1:t]));
                Gamma(i,i) = prod( p([1:currClassIdx-1 , currClassIdx+1:t]));
            end
        else
            for i = 1:ntr1
                if Ytr1(i,:) == 1
                    Gamma(i,i) = 1 - p_c1;
                else
                    Gamma(i,i) = 1 - p_c2;
                end
            end
        end
        
        % Precompute cov mat
        XtX = Xtr1'*Xtr1;
        XtY = Xtr1'*Gamma*Ytr1;
%         G = diag(Gamma)';
%         XtY = Xtr1'* ( Ytr1 .* G(ones(1,t),:)');
%         XtY = Xtr1'* ( Ytr1 .* sqrt(G(ones(1,t),:))');

        lstar = 0;      % Best lambda
        bestAcc = 0;    % Highest accuracy
        for lidx = 1:numel(lrng)

            l = lrng(lidx);

            % Train on TR1
            w = (XtX + ntr1*l*eye(d)) \ XtY;

            % Predict validation labels
            Yval1pred_raw = Xval1 * w;

            % Compute current validation accuracy
            
            if t > 2
                Yval1pred = ds.scoresToClasses(Yval1pred_raw);
                [currAcc , ~] = weightedAccuracy2( Yval1, Yval1pred , classes);
            else

                CM = confusionmat(Yval1,sign(Yval1pred_raw));
                CM = CM ./ repmat(sum(CM,2),1,2);
                currAcc = trace(CM)/2;                
            end
            results.inc_rlsc_yesreb2.valAcc(k,lidx) = currAcc;

            if currAcc > bestAcc
                bestAcc = currAcc;
                lstar = l;
            end

            % Compute current test accuracy
            Ytepred_raw = Xte * w;
            
            if t > 2
                Ytepred = ds.scoresToClasses(Ytepred_raw);
                [currAcc , ~] = weightedAccuracy2( Yte, Ytepred , classes);
            else
                CM = confusionmat(Yte,sign(Ytepred_raw));
                CM = CM ./ repmat(sum(CM,2),1,2);
                currAcc = trace(CM)/2;                
            end
            results.inc_rlsc_yesreb2.teAcc(k,lidx) = currAcc;
        end

        % Retrain on full training set with selected model parameters,
        %  if requested

        if retrain == 1

            % Compute rebalancing matrix Gamma
            Gamma1 = zeros(ntr);
            if t > 2
                for i = 1:ntr
                    currClassIdx = find(Ytr(i,:) == 1);
%                     Gamma1(i,i) = 1 / p(currClassIdx);
%                     Gamma1(i,i) = prod(t  * ds.trainClassFreq([1:currClassIdx-1 , currClassIdx+1:t]));
%                     Gamma1(i,i) = prod(t  * p([1:currClassIdx-1 , currClassIdx+1:t]));
                    Gamma1(i,i) = prod( p([1:currClassIdx-1 , currClassIdx+1:t]));
                end
            else
                for i = 1:ntr
                    if Ytr(i,:) == 1
                        Gamma1(i,i) = 1 - p_c1;
                    else
                        Gamma1(i,i) = 1 - p_c2;
                    end
                end
            end
            % Compute cov mat
            XtX = Xtr'*Xtr;
            XtY = Xtr'*Gamma1*Ytr;    
%             G1 = diag(Gamma1)';
%             XtY = Xtr'* ( Ytr .* G1(ones(1,t),:)');
%             XtY = Xtr'* ( Ytr .* sqrt(G1(ones(1,t),:))');

            % Train on TR
            w = (XtX + ntr*lstar*eye(d)) \ XtY;
        end

        % Test on test set & compute accuracy

        % Predict test labels
        Ytepred_raw = Xte * w;
        
        % Compute current accuracy
            
        if t > 2
            Ytepred = ds.scoresToClasses(Ytepred_raw);
            [currAcc , CM] = weightedAccuracy2( Yte, Ytepred , classes);
        else
            CM = confusionmat(Yte,sign(Ytepred_raw));
            CM = CM ./ repmat(sum(CM,2),1,2);
            currAcc = trace(CM)/2;
        end
        
        results.inc_rlsc_yesreb2.ntr = ntr;
        results.inc_rlsc_yesreb2.nte = nte;
        results.inc_rlsc_yesreb2.testAccBuf(k) = currAcc;
        results.inc_rlsc_yesreb2.testCM(k,:,:) = CM;
        results.inc_rlsc_yesreb2.bestValAccBuf(k) = bestAcc;

    end    
    
    
    
end

%% Print results

clc
display('Results');
display(' ');

if run_bat_rlsc_yesreb == 1    

    display('Batch RLSC, exact rebalancing (sqrt(Gamma))');
    best_val_acc_avg = mean(results.bat_rlsc_yesreb.bestValAccBuf);
    best_val_acc_std = std(results.bat_rlsc_yesreb.bestValAccBuf,1);

    display(['Best validation accuracy = ', num2str(best_val_acc_avg) , ' +/- ' , num2str(best_val_acc_std)])

    test_acc_avg = mean(results.bat_rlsc_yesreb.testAccBuf);
    test_acc_std = std(results.bat_rlsc_yesreb.testAccBuf,1);

    display(['Test accuracy = ', num2str(test_acc_avg) , ' +/- ' , num2str(test_acc_std)])
    display(' ');
end

if run_bat_rlsc_yesreb2 == 1
    display('Batch RLSC, exact rebalancing (Gamma)');
    best_val_acc_avg = mean(results.bat_rlsc_yesreb2.bestValAccBuf);
    best_val_acc_std = std(results.bat_rlsc_yesreb2.bestValAccBuf,1);

    display(['Best validation accuracy = ', num2str(best_val_acc_avg) , ' +/- ' , num2str(best_val_acc_std)])

    test_acc_avg = mean(results.bat_rlsc_yesreb2.testAccBuf);
    test_acc_std = std(results.bat_rlsc_yesreb2.testAccBuf,1);

    display(['Test accuracy = ', num2str(test_acc_avg) , ' +/- ' , num2str(test_acc_std)])
    display(' ');    
end

if run_bat_rlsc_noreb == 1    

    display('Batch RLSC, no rebalancing');
    best_val_acc_avg = mean(results.bat_rlsc_noreb.bestValAccBuf);
    best_val_acc_std = std(results.bat_rlsc_noreb.bestValAccBuf,1);

    display(['Best validation accuracy = ', num2str(best_val_acc_avg) , ' +/- ' , num2str(best_val_acc_std)])

    test_acc_avg = mean(results.bat_rlsc_noreb.testAccBuf);
    test_acc_std = std(results.bat_rlsc_noreb.testAccBuf,1);

    display(['Test accuracy = ', num2str(test_acc_avg) , ' +/- ' , num2str(test_acc_std)]);
    display(' ');
end

if run_inc_rlsc_yesreb == 1    

    display('Incremental RLSC, with recoding (sqrt(Gamma))');
    best_val_acc_avg = mean(results.inc_rlsc_yesreb.bestValAccBuf);
    best_val_acc_std = std(results.inc_rlsc_yesreb.bestValAccBuf,1);

    display(['Best validation accuracy = ', num2str(best_val_acc_avg) , ' +/- ' , num2str(best_val_acc_std)])

    test_acc_avg = mean(results.inc_rlsc_yesreb.testAccBuf);
    test_acc_std = std(results.inc_rlsc_yesreb.testAccBuf,1);

    display(['Test accuracy = ', num2str(test_acc_avg) , ' +/- ' , num2str(test_acc_std)]);
    display(' ');
end


if run_inc_rlsc_yesreb2 == 1    

    display('Incremental RLSC, with recoding (Gamma)');
    best_val_acc_avg = mean(results.inc_rlsc_yesreb2.bestValAccBuf);
    best_val_acc_std = std(results.inc_rlsc_yesreb2.bestValAccBuf,1);

    display(['Best validation accuracy = ', num2str(best_val_acc_avg) , ' +/- ' , num2str(best_val_acc_std)])

    test_acc_avg = mean(results.inc_rlsc_yesreb2.testAccBuf);
    test_acc_std = std(results.inc_rlsc_yesreb2.testAccBuf,1);

    display(['Test accuracy = ', num2str(test_acc_avg) , ' +/- ' , num2str(test_acc_std)]);
    display(' ');
end


%% Save workspace

if saveResult == 1

    save([resdir '/workspace.mat']);
end

%% Plots


if run_bat_rlsc_yesreb == 1    

    % Batch RLSC, exact rebalancing
    % figure
    % hold on
    % title({ 'Batch RLSC, exact rebalancing' ; ['Test accuracy over ' , num2str(numrep) , ' runs'] } );
    % boxplot(results.bat_rlsc_yesreb.testAccBuf')
    % hold off 
    % 
    % figure
    % hold on
    % title({ 'Batch RLSC, exact rebalancing' ; ['Validation accuracy over ' , num2str(numrep) , ' runs'] } );
    % boxplot(results.bat_rlsc_yesreb.bestValAccBuf')
    % hold off 

    % figure
    % hold on
    % title({'Batch RLSC, exact rebalancing' ; 'Test accuracy vs \lambda'})
    % contourf(lrng,1:numrep,results.bat_rlsc_yesreb.teAcc, 100, 'LineWidth',0);
    % set(gca,'Xscale','log');
    % xlabel('\lambda')
    % ylabel('Repetition')
    % colorbar
    % hold off

    figure
    hold on
    title({'Batch RLSC, exact rebalancing  (sqrt(Gamma))' ; 'Test accuracy vs \lambda'})
    bandplot( lrng , results.bat_rlsc_yesreb.teAcc , 'red' , 0.1 , 1 , 2, '-');
    xlabel('\lambda')
    ylabel('Test accuracy')
    hold off

    % figure
    % hold on
    % title({'Batch RLSC, exact rebalancing' ; 'Validation accuracy vs \lambda'})
    % contourf(lrng,1:numrep,results.bat_rlsc_yesreb.valAcc, 100, 'LineWidth',0);
    % set(gca,'Xscale','log');
    % xlabel('\lambda')
    % ylabel('Repetition')
    % colorbar
    % hold off

    % figure
    % hold on
    % title({'Batch RLSC, exact rebalancing' ; 'Validation accuracy vs \lambda'})
    % bandplot( lrng , results.bat_rlsc_yesreb.valAcc , 'red' , 0.1 , 1 , 2, '-');
    % xlabel('\lambda')
    % ylabel('Validation accuracy')
    % hold off

end

if run_bat_rlsc_yesreb2 == 1    

    % Batch RLSC, exact rebalancing
    % figure
    % hold on
    % title({ 'Batch RLSC, exact rebalancing' ; ['Test accuracy over ' , num2str(numrep) , ' runs'] } );
    % boxplot(results.bat_rlsc_yesreb.testAccBuf')
    % hold off 
    % 
    % figure
    % hold on
    % title({ 'Batch RLSC, exact rebalancing' ; ['Validation accuracy over ' , num2str(numrep) , ' runs'] } );
    % boxplot(results.bat_rlsc_yesreb.bestValAccBuf')
    % hold off 

    % figure
    % hold on
    % title({'Batch RLSC, exact rebalancing' ; 'Test accuracy vs \lambda'})
    % contourf(lrng,1:numrep,results.bat_rlsc_yesreb.teAcc, 100, 'LineWidth',0);
    % set(gca,'Xscale','log');
    % xlabel('\lambda')
    % ylabel('Repetition')
    % colorbar
    % hold off

    figure
    hold on
    title({'Batch RLSC, exact rebalancing (Gamma)' ; 'Test accuracy vs \lambda'})
    bandplot( lrng , results.bat_rlsc_yesreb2.teAcc , 'red' , 0.1 , 1 , 2, '-');
    xlabel('\lambda')
    ylabel('Test accuracy')
    hold off

    % figure
    % hold on
    % title({'Batch RLSC, exact rebalancing' ; 'Validation accuracy vs \lambda'})
    % contourf(lrng,1:numrep,results.bat_rlsc_yesreb.valAcc, 100, 'LineWidth',0);
    % set(gca,'Xscale','log');
    % xlabel('\lambda')
    % ylabel('Repetition')
    % colorbar
    % hold off

    % figure
    % hold on
    % title({'Batch RLSC, exact rebalancing' ; 'Validation accuracy vs \lambda'})
    % bandplot( lrng , results.bat_rlsc_yesreb.valAcc , 'red' , 0.1 , 1 , 2, '-');
    % xlabel('\lambda')
    % ylabel('Validation accuracy')
    % hold off

end

if run_bat_rlsc_noreb == 1    

    % Batch RLSC, no rebalancing
    % figure
    % hold on
    % title({ 'Batch RLSC, no rebalancing' ; ['Test accuracy over ' , num2str(numrep) , ' runs'] } );
    % boxplot(results.bat_rlsc_noreb.testAccBuf')
    % hold off 
    % 
    % figure
    % hold on
    % title({ 'Batch RLSC, no rebalancing' ; ['Validation accuracy over ' , num2str(numrep) , ' runs'] } );
    % boxplot(results.bat_rlsc_noreb.bestValAccBuf')
    % hold off 

    % figure
    % hold on
    % title({'Batch RLSC, no rebalancing' ; 'Test accuracy vs \lambda'})
    % contourf(lrng,1:numrep,results.bat_rlsc_noreb.teAcc, 100, 'LineWidth',0);
    % set(gca,'Xscale','log');
    % xlabel('\lambda')
    % ylabel('Repetition')
    % colorbar
    % hold off

    figure
    hold on
    title({'Batch RLSC, no rebalancing' ; 'Test accuracy vs \lambda'})
    bandplot( lrng , results.bat_rlsc_noreb.teAcc , 'red' , 0.1 , 1 , 2, '-');
    xlabel('\lambda')
    ylabel('Test accuracy')
    hold off

    % figure
    % hold on
    % title({'Batch RLSC, no rebalancing' ; 'Validation accuracy vs \lambda'})
    % contourf(lrng,1:numrep,results.bat_rlsc_noreb.valAcc, 100, 'LineWidth',0);
    % set(gca,'Xscale','log');
    % xlabel('\lambda')
    % ylabel('Repetition')
    % colorbar
    % hold off

    % figure
    % hold on
    % title({'Batch RLSC, no rebalancing' ; 'Validation accuracy vs \lambda'})
    % bandplot( lrng , results.bat_rlsc_noreb.valAcc , 'red' , 0.1 , 1 , 2, '-');
    % xlabel('\lambda')
    % ylabel('Validation accuracy')
    % hold off
end



if run_inc_rlsc_yesreb == 1    

    % Batch RLSC, exact rebalancing
    % figure
    % hold on
    % title({ 'Batch RLSC, exact rebalancing' ; ['Test accuracy over ' , num2str(numrep) , ' runs'] } );
    % boxplot(results.bat_rlsc_yesreb.testAccBuf')
    % hold off 
    % 
    % figure
    % hold on
    % title({ 'Batch RLSC, exact rebalancing' ; ['Validation accuracy over ' , num2str(numrep) , ' runs'] } );
    % boxplot(results.bat_rlsc_yesreb.bestValAccBuf')
    % hold off 

    % figure
    % hold on
    % title({'Batch RLSC, exact rebalancing' ; 'Test accuracy vs \lambda'})
    % contourf(lrng,1:numrep,results.bat_rlsc_yesreb.teAcc, 100, 'LineWidth',0);
    % set(gca,'Xscale','log');
    % xlabel('\lambda')
    % ylabel('Repetition')
    % colorbar
    % hold off

    figure
    hold on
    title({'Incremental RLSC with recoding (sqrt(Gamma))' ; 'Test accuracy vs \lambda'})
    bandplot( lrng , results.inc_rlsc_yesreb.teAcc , 'red' , 0.1 , 1 , 2, '-');
    xlabel('\lambda')
    ylabel('Test accuracy')
    hold off

    % figure
    % hold on
    % title({'Batch RLSC, exact rebalancing' ; 'Validation accuracy vs \lambda'})
    % contourf(lrng,1:numrep,results.bat_rlsc_yesreb.valAcc, 100, 'LineWidth',0);
    % set(gca,'Xscale','log');
    % xlabel('\lambda')
    % ylabel('Repetition')
    % colorbar
    % hold off

    % figure
    % hold on
    % title({'Batch RLSC, exact rebalancing' ; 'Validation accuracy vs \lambda'})
    % bandplot( lrng , results.bat_rlsc_yesreb.valAcc , 'red' , 0.1 , 1 , 2, '-');
    % xlabel('\lambda')
    % ylabel('Validation accuracy')
    % hold off

end




if run_inc_rlsc_yesreb2 == 1    

    % Batch RLSC, exact rebalancing
    % figure
    % hold on
    % title({ 'Batch RLSC, exact rebalancing' ; ['Test accuracy over ' , num2str(numrep) , ' runs'] } );
    % boxplot(results.bat_rlsc_yesreb.testAccBuf')
    % hold off 
    % 
    % figure
    % hold on
    % title({ 'Batch RLSC, exact rebalancing' ; ['Validation accuracy over ' , num2str(numrep) , ' runs'] } );
    % boxplot(results.bat_rlsc_yesreb.bestValAccBuf')
    % hold off 

    % figure
    % hold on
    % title({'Batch RLSC, exact rebalancing' ; 'Test accuracy vs \lambda'})
    % contourf(lrng,1:numrep,results.bat_rlsc_yesreb.teAcc, 100, 'LineWidth',0);
    % set(gca,'Xscale','log');
    % xlabel('\lambda')
    % ylabel('Repetition')
    % colorbar
    % hold off

    figure
    hold on
    title({'Incremental RLSC with recoding (Gamma)' ; 'Test accuracy vs \lambda'})
    bandplot( lrng , results.inc_rlsc_yesreb2.teAcc , 'red' , 0.1 , 1 , 2, '-');
    xlabel('\lambda')
    ylabel('Test accuracy')
    hold off

    % figure
    % hold on
    % title({'Batch RLSC, exact rebalancing' ; 'Validation accuracy vs \lambda'})
    % contourf(lrng,1:numrep,results.bat_rlsc_yesreb.valAcc, 100, 'LineWidth',0);
    % set(gca,'Xscale','log');
    % xlabel('\lambda')
    % ylabel('Repetition')
    % colorbar
    % hold off

    % figure
    % hold on
    % title({'Batch RLSC, exact rebalancing' ; 'Validation accuracy vs \lambda'})
    % bandplot( lrng , results.bat_rlsc_yesreb.valAcc , 'red' , 0.1 , 1 , 2, '-');
    % xlabel('\lambda')
    % ylabel('Validation accuracy')
    % hold off

end


%%  Play sound

load gong;
player = audioplayer(y, Fs);
play(player);