addpath(genpath('/home/kammo/Repos/Enitor/utils'));
clearAllButBP;
close all;

%% Experiments setup
run_batch = 1;
run_incremental_balanced_parallel = 1;
run_batch_realistic_rebalanced_loss = 1;
run_incremental_realistic_rebalanced_label = 1;

%% Load data

% Random dataset

ntr = 1000;     % Number of training samples
nte = 1000;     % Number of test samples
n = ntr + nte;  % Total number of examples
d = 100;        % Dimensionality
t = 10;         % Number of classes

if mod(n,t) >0
    error('n cannot be divided by t')
end

X = rand(n,d);
% tmp = randi(t,n,1);
tmp = repmat(1:10,n/t,1);
tmp = reshape(tmp,n,1);
tmp = tmp(randperm(n));
Y = zeros(n,t);
for i = 1:n
    Y(i,tmp(i)) = 1;
end
clear tmp;

Xtr = X(1:ntr,:);
Xte = X(ntr+1:ntr+nte,:);
Ytr = Y(1:ntr,:);
Yte = Y(ntr+1:ntr+nte,:);

%% Batch RLSC
% Naive Linear Regularized Least Squares Classifier, 
% with Tikhonov regularization parameter selection

if run_batch == 1

    retrain = 1;
    trainPart = 0.8;

    % Parameter selection
    lrng = logspace(1 , -6 , 7);

    % Splitting
    ntr1 = round(ntr*trainPart);
    nval1 = round(ntr*(1-trainPart));
    tr1idx = 1:ntr1;
    val1idx = (1:nval1) + ntr1;
    Xtr1 = Xtr(tr1idx,:);
    Xval1 = Xtr(val1idx,:);
    Ytr1 = Ytr(tr1idx,:);
    Yval1 = Ytr(val1idx,:);

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

        % Encode output
        Yval1pred = zeros(nval1,t);
        for i = 1:nval1
            [~,maxIdx] = max(Yval1pred_raw(i,:));
            Yval1pred(i,maxIdx) = 1;
        end
        clear Yval1pred_raw;

        % Compute current accuracy
        C = transpose(bsxfun(@eq, Yval1', Yval1pred'));
        D = sum(C,2);
        E = D == t;
        numCorrect = sum(E);
        currAcc = (numCorrect / nval1);     

        if currAcc > bestAcc
            bestAcc = currAcc;
            lstar = l;
        end
    end

    %% Retrain on full training set with selected model parameters,
    %  if requested

    if retrain == 1

        % Compute cov mat and b
        XtX = Xtr'*Xtr;
        XtY = Xtr'*Ytr;

        % Train on TR1
        w = (XtX + ntr*lstar*eye(d)) \ XtY;

    end

    %% Test on test set & compute accuracy


    % Predict validation labels
    Ytepred_raw = Xte * w;

    % Encode output
    Ytepred = zeros(nte,t);
    for i = 1:nte
    [~,maxIdx] = max(Ytepred_raw(i,:));
    Ytepred(i,maxIdx) = 1;
    end
    clear Ytepred_raw;

    % Compute test set accuracy
    C = transpose(bsxfun(@eq, Yte', Ytepred'));
    D = sum(C,2);
    E = D == t;
    numCorrect = sum(E);
    testAcc = (numCorrect / nte);     
end

%% Incremental balanced parallel

% Configuration
retrain = 1;
nuptr = 80;     % Number of training examples per update
nupval = 20;    % Number of validation examples per update
currUpIdx = 1;  % Current index of the first example of the update minibatch
nlambda = 8;

if run_incremental_balanced_parallel == 1

    lrng = logspace(1 , -6 , nlambda);    % Lambda range
    numUpdates = floor(ntr / (nuptr + nupval));     % Number of update steps
    
    R = cell(1,nlambda);
    testAcc = cell(1,nlambda);
    lstarqueue = [];
    bestAccqueue = [];
    
    for k = 1:numUpdates
        
        % Get data chunks
        Xuptr = Xtr(currUpIdx:(currUpIdx+nuptr-1),:);
        Yuptr = Ytr(currUpIdx:(currUpIdx+nuptr-1),:);
        Xupval = Xtr(currUpIdx+nuptr:(currUpIdx+nuptr+nupval-1),:);
        Yupval = Ytr(currUpIdx+nuptr:(currUpIdx+nuptr+nupval-1),:);

        currUpIdx = currUpIdx + nuptr + nupval;
        
        if k == 1
            % Compute cov mat and b
            XtX = Xuptr'*Xuptr;
            XtY = Xuptr'*Yuptr;   
        else

            % Update XtY term
            XtY = XtY + Xuptr' * Yuptr;
        end
        
        lstar = max(lrng);      % Best lambda
        bestAcc = 0;    % Highest accuracy    

        for lidx = 1:nlambda

            l = lrng(lidx);
            
            if k == 1
                % Compute first Cholesky factorization of XtX + n * lambda * I
                R{lidx} = chol(XtX + nuptr * l * eye(d),'upper');  
            else
                % Update Cholesky factor
                R{lidx} = cholupdatek(R{lidx},Xuptr);                
            end
            
           %% Training
            w = R{lidx} \ (R{lidx}' \ XtY );

           %% Validation
            % Predict validation labels
            Yupvalpred_raw = Xupval * w;

            % Encode output
            Yupvalpred = zeros(nupval,t);
            for i = 1:nupval
                [~,maxIdx] = max(Yupvalpred_raw(i,:));
                Yupvalpred(i,maxIdx) = 1;
            end
            clear Yupvalpred_raw;

            % Compute current accuracy
            C = transpose(bsxfun(@eq, Yupval', Yupvalpred'));
            D = sum(C,2);
            E = D == t;
            numCorrect = sum(E);
            currAcc = (numCorrect / nupval);     

            if currAcc > bestAcc
                bestAcc = currAcc;
                lstar = l;
            end
        end
        
        lstarqueue = [lstarqueue , lstar];
        bestAccqueue = [bestAccqueue , bestAcc];
        
       %% Retraining

        if retrain == 1
            for lidx = 1:nlambda
                % Update Cholesky factor
                R{lidx} = cholupdatek(R{lidx},Xupval);

            end
            % Update XtY term
            XtY = XtY + Xupval' * Yupval;
        end
        
       %% Testing
       
        for lidx = 1:nlambda

            l = lrng(lidx);

            % Predict test labels
            Ytepred_raw = Xte * w;

            % Encode output
            Ytepred = zeros(nte,t);
            for i = 1:nte
                [~,maxIdx] = max(Ytepred_raw(i,:));
                Ytepred(i,maxIdx) = 1;
            end
            clear Yuptestpred_raw;

            % Compute accuracy
            C = transpose(bsxfun(@eq, Yte', Ytepred'));
            D = sum(C,2);
            E = D == t;
            numCorrect = sum(E);
            testAcc{lidx} = [testAcc{lidx} , (numCorrect / nte)];
        end
    end
    
    %% Plots
    
    % Test Accuracy evolution for different lambdas
    figure
    mesh(cell2mat(testAcc'))
    title('Test Accuracy evolution for different \lambda')
    xlabel('k')    
    ylabel('\lambda')
    zlabel('Accuracy')    

    % Best lambdas evolution
    figure
    semilogy(lstarqueue)
    title('\lambda* evolution for different \lambda')
    xlabel('k')    
    ylabel('\lambda*')
    
    % Best accuracies evolution
    figure
    plot(bestAccqueue)
    title('Best validation accuracies evolution for different \lambda')
    xlabel('k')    
    ylabel('Best validation accuracies')

end

%% Batch realistic with loss rebalancing
if run_batch_realistic_rebalanced_loss == 1

end


%% Incremental realistic with rebalancing via label reweighting
if run_incremental_realistic_rebalanced_label == 1
    
    %% Format dataset in class-specific cells
    
    X_c = cell(1,t);
    Y_c = cell(1,t);    
    Xtr_c = cell(1,t);
    Ytr_c = cell(1,t);    
    Xte_c = cell(1,t);
    Yte_c = cell(1,t);

    for sampleidx = 1:n
        for classidx = 1:t
            if Y(sampleidx,classidx) == 1
%                 Y_c{classidx}(sampleidx,:) = Y(sampleidx,:);
%                 X_c{classidx}(sampleidx,:) = X(sampleidx,:);
                Y_c{classidx} = [ Y_c{classidx} ; Y(sampleidx,:)];
                X_c{classidx} = [ X_c{classidx} ; X(sampleidx,:)];
%                 break
            end
        end
    end
    
    for classidx = 1:t
        Xtr_c{classidx} = X_c{classidx}(1:(ntr/t),:);
        Ytr_c{classidx} = Y_c{classidx}(1:(ntr/t),:);    
        Xte_c{classidx} = X_c{classidx}((ntr/t)+1:(ntr+nte)/t,:);
        Yte_c{classidx} = Y_c{classidx}((ntr/t)+1:(ntr+nte)/t,:);
    end
end
