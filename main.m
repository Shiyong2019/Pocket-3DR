addpath(genpath(fileparts(which(mfilename))))

%% Program arguments
dataset = 'cpl';
calib = 'calib_AV_X2S_4MPIX.mat';
% Dense reconstruction pairs
drp = [1 ...
    %fix(length(dir(['ims/' dataset '*.jpg']))/8)+1 ...
    %fix(2*length(dir(['ims/' dataset '*.jpg']))/8)+1 ...
    %fix(3*length(dir(['ims/' dataset '*.jpg']))/8)+1 ...
    %fix(4*length(dir(['ims/' dataset '*.jpg']))/8)+1 ...
    %fix(5*length(dir(['ims/' dataset '*.jpg']))/8)+1 ...
    fix(6*length(dir(['ims/' dataset '*.jpg']))/8)+1 ...
    %fix(7*length(dir(['ims/' dataset '*.jpg']))/8)+1 ...
    ];

%% Reading image dataset
disp(['Running pipeline for dataset "' dataset '"'])
imsDir = dir(['ims/' dataset '*.jpg']);
disp(['Dataset contains ' num2str(length(imsDir)) ' images'])
load(calib)
disp('Calibration matrix: '), disp(K)
if exist('d','var')
    disp('Radial distortion parameters: '), disp(d)
end

imsNames = {imsDir.name};
imsNo = length(imsNames);
Cim = cell(1,imsNo);
for i = 1:length(imsNames)
    Cim{i} = imread(imsNames{i});
end
if exist('d','var')
    Cim = UndistortImages(Cim,K,d);
end

%% Computing correspondences
CfeatPts = cell(1,imsNo);
for i = 1:imsNo
    disp(['Feature points estimation: image ' num2str(i) ' of ' num2str(imsNo)])
    CfeatPts{i} = EstimateFeaturePoints(Cim{i});
end
Ccorrs = cell(1,imsNo-1);
for i = 1:imsNo-1
    disp(['Feature matching: pair ' num2str(i) ' of ' num2str(imsNo-1)])
    Ccorrs{i} = MatchFeaturePoints(CfeatPts{i}, CfeatPts{i+1});
end

%% Fundamental Matrix estimation
CcorrsIn = cell(1,imsNo-1);
CF = cell(1,imsNo-1);
for i = 1:imsNo-1
    disp(['Fundamental Matrix estimation: pair ' num2str(i) ' of ' num2str(imsNo-1)])
    [CF{i}, Cinliers] = RANSAC(num2cell(Ccorrs{i},1),...
        @EstimateFundamentalMatrix, 8, @SampsonDistance, 10);
    CcorrsIn{i} = cell2mat(Cinliers);
    CF(i) = EstimateFundamentalMatrix(Cinliers);
end

%% Background Filtering
CcorrsInFil = cell(1,imsNo-1);
for i = 1:imsNo-1
    disp(['Background Filtering: pair ' num2str(i) ' of ' num2str(imsNo-1)])
    P = EstimateRealPose(K'*CF{i}*K, NormalizeCorrs(CcorrsIn{i},K));
    CcorrsInFil{i} = FilterBackgroundFromCorrs(...
        K*CANONICAL_POSE, K*P, CcorrsIn{i}, 3);
    CF(i) = EstimateFundamentalMatrix(num2cell(CcorrsInFil{i},1));
end

%% Essential Matrix from Fundamental Matrix
CE = cell(1,imsNo-1);
CcorrsNormInFil = cell(1,imsNo-1);
for i = 1:imsNo-1
    disp(['Essential Matrix from Fundamental Matrix: '...
        num2str(i) ' of ' num2str(imsNo-1)])
    CE{i} = K'*CF{i}*K/norm(K'*CF{i}*K)*sqrt(2)/2;
    CcorrsNormInFil{i} = NormalizeCorrs(CcorrsInFil{i}, K);
end

%% Structure from Motion
disp('Pose estimation: default first pair')
CP = cell(1,imsNo);
CP{1} = CANONICAL_POSE; 
CP{2} = EstimateRealPose(CE{1}, CcorrsNormInFil{1});

LOCALBA_OCCUR_PER1 = 4;
LOCALBA_OCCUR_PER2 = 6;
LOCALBA_OCCUR_PER3 = 8;
LOCALBA_OCCUR_PER4 = 10;
for i = 2:imsNo-1
    disp(['Pose estimation: ' num2str(i+1) ' of ' num2str(imsNo)])
    CP{i+1} = EstimateRealPose(CE{i}, CcorrsNormInFil{i}, CP{i});
    TrackedCorrs = CascadeTrack({CcorrsNormInFil{i-1}, CcorrsNormInFil{i}});
    TrackedCorrsIso = IsolateTransitiveCorrs(TrackedCorrs);
    disp(['Transitivity: ' num2str(size(TrackedCorrsIso,2))])
    CP{i+1} = OptimizeTranslationVector(CP{i-1}, CP{i}, CP{i+1}, TrackedCorrsIso);
    CP{i+1} = MiniBundleAdjustment(CP{i-1}, CP{i}, CP{i+1}, TrackedCorrsIso);
    
    if ~mod(i-1, LOCALBA_OCCUR_PER1-2)
        disp('Local Bundle Adjustment 1...')
        disp(['Refine ' num2str(i-(LOCALBA_OCCUR_PER1-2)) '->' num2str(i+1)])
        C = IsolateTransitiveCorrs(CascadeTrack(...
            CcorrsNormInFil(i-(LOCALBA_OCCUR_PER1-2) : i)), 'displaySize');
        if size(C,2) > 1
            CPBA = BundleAdjustment(CP(i-(LOCALBA_OCCUR_PER1-2) : i+1), C);
            CP(i-(LOCALBA_OCCUR_PER1-2) : i+1) = CPBA;
        end
    end
    if ~mod(i-1, LOCALBA_OCCUR_PER2-2)
        disp('Local Bundle Adjustment 2...')
        disp(['Refine ' num2str(i-(LOCALBA_OCCUR_PER2-2)) '->' num2str(i+1)])
        C = IsolateTransitiveCorrs(CascadeTrack(...
            CcorrsNormInFil(i-(LOCALBA_OCCUR_PER2-2) : i)), 'displaySize'); 
        if size(C,2) > 1
            CPBA = BundleAdjustment(CP(i-(LOCALBA_OCCUR_PER2-2) : i+1), C);
            CP(i-(LOCALBA_OCCUR_PER2-2) : i+1) = CPBA;
        end
    end
    if ~mod(i-1, LOCALBA_OCCUR_PER3-2)
        disp('Local Bundle Adjustment 3...')
        disp(['Refine ' num2str(i-(LOCALBA_OCCUR_PER3-2)) '->' num2str(i+1)])
        C = IsolateTransitiveCorrs(CascadeTrack(...
            CcorrsNormInFil(i-(LOCALBA_OCCUR_PER3-2) : i)), 'displaySize'); 
        if size(C,2) > 1
            CPBA = BundleAdjustment(CP(i-(LOCALBA_OCCUR_PER3-2) : i+1), C);
            CP(i-(LOCALBA_OCCUR_PER3-2) : i+1) = CPBA;
        end
    end
    if ~mod(i-1, LOCALBA_OCCUR_PER4-2)
        disp('Local Bundle Adjustment 4...')
        disp(['Refine ' num2str(i-(LOCALBA_OCCUR_PER4-2)) '->' num2str(i+1)])
        C = CascadeTrack(CcorrsNormInFil(i-(LOCALBA_OCCUR_PER4-2) : i)); 
        if size(C,2) > 1
            CPBA = BundleAdjustment(CP(i-(LOCALBA_OCCUR_PER4-2) : i+1), C);
            CP(i-(LOCALBA_OCCUR_PER4-2) : i+1) = CPBA;
        end
    end
end

disp('Last Local Bundle Adjustments...')
if imsNo > LOCALBA_OCCUR_PER1
    disp(['Refine ' num2str((imsNo-1)-(LOCALBA_OCCUR_PER1-2)) '->' num2str(imsNo)])
    C = IsolateTransitiveCorrs(CascadeTrack(...
        CcorrsNormInFil((imsNo-1)-(LOCALBA_OCCUR_PER1-2) : imsNo-1)), 'displaySize');
    if size(C,2) > 1
        CPBA = BundleAdjustment(CP((imsNo-1)-(LOCALBA_OCCUR_PER1-2) : imsNo), C);
        CP((imsNo-1)-(LOCALBA_OCCUR_PER1-2) : imsNo) = CPBA;
    end
end
if imsNo > LOCALBA_OCCUR_PER2
    disp(['Refine ' num2str((imsNo-1)-(LOCALBA_OCCUR_PER2-2)) '->' num2str(imsNo)])
    C = IsolateTransitiveCorrs(CascadeTrack(...
        CcorrsNormInFil((imsNo-1)-(LOCALBA_OCCUR_PER2-2) : imsNo-1)), 'displaySize');
    if size(C,2) > 1
        CPBA = BundleAdjustment(CP((imsNo-1)-(LOCALBA_OCCUR_PER2-2) : imsNo), C);
        CP((imsNo-1)-(LOCALBA_OCCUR_PER2-2) : imsNo) = CPBA;
    end
end
if imsNo > LOCALBA_OCCUR_PER3
    disp(['Refine ' num2str((imsNo-1)-(LOCALBA_OCCUR_PER3-2)) '->' num2str(imsNo)])
    C = IsolateTransitiveCorrs(CascadeTrack(...
        CcorrsNormInFil((imsNo-1)-(LOCALBA_OCCUR_PER3-2) : imsNo-1)), 'displaySize');
    if size(C,2) > 1
        CPBA = BundleAdjustment(CP((imsNo-1)-(LOCALBA_OCCUR_PER3-2) : imsNo), C);
        CP((imsNo-1)-(LOCALBA_OCCUR_PER3-2) : imsNo) = CPBA;
    end
end
if imsNo > LOCALBA_OCCUR_PER4
    disp(['Refine ' num2str((imsNo-1)-(LOCALBA_OCCUR_PER4-2)) '->' num2str(imsNo)])
    C = CascadeTrack(CcorrsNormInFil((imsNo-1)-(LOCALBA_OCCUR_PER4-2) : imsNo-1));
    if size(C,2) > 1
        CPBA = BundleAdjustment(CP((imsNo-1)-(LOCALBA_OCCUR_PER4-2) : imsNo), C);
        CP((imsNo-1)-(LOCALBA_OCCUR_PER4-2) : imsNo) = CPBA;
    end
end

%% Global Bundle Adjustment
disp('Global Bundle Adjustment')
C = CascadeTrack(CcorrsNormInFil);
CPBA = BundleAdjustment(CP,C);
X = TriangulateCascade(CPBA,C);

PlotSparse(CP,X);

%% Dense Matching
CX = cell(1,length(drp));
CC = cell(1,length(drp));
CXSc = cell(1,length(drp));
CCSc = cell(1,length(drp));
for i = 1:length(drp)
    disp(['Dense Matching: pair ' num2str(i) ' of ' num2str(length(drp))])
    [CX{i}, CC{i}, CXSc{i}, CCSc{i}] = RectifyAndDenseTriangulate(...
        CropBackground(...
        Cim{drp(i)},CcorrsInFil{drp(i)}(1:2,:),1.1),...
        CropBackground(...
        Cim{drp(i)+1},CcorrsInFil{drp(i)}(3:4,:),1.1),...
        CF{drp(i)}, K*CP{drp(i)}, K*CP{drp(i)+1}, 'denoise',...
        {'plotCorrespondences','plotDisparityMap'});
end

PlotDense(cell2mat(CX),cell2mat(CC))

%% Remeshing and Recoloring
CXFil = cell(1,length(drp));
CCFil = cell(1,length(drp));
CNFil = cell(1,length(drp));
for i = 1:length(drp)
    disp(['Computing normals: set ' num2str(i) ' of ' num2str(length(drp))])
    [CNFil{i}, filInd] = ComputeNormalsAndFilter(CXSc{i});
    CXFil{i} = CX{i}(:,filInd);
    CCFil{i} = CC{i}(:,filInd);
end

disp('Remeshing')
RemeshToPly([dataset '-colored.ply'],...
    cell2mat(CXFil), cell2mat(CNFil), cell2mat(CCFil))

PlotDense(cell2mat(CXFil),cell2mat(CCFil))

%% Retexturing