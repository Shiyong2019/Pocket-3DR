function PlotSparse(CP, X)
%PLOTSPARSE Summary of this function goes here
%   Detailed explanation goes here
CR = cellfun(@(P) P(1:3,1:3), CP, 'UniformOutput', false);
CC = cellfun(@(P) -P(1:3,1:3)'*P(1:3,4), CP, 'UniformOutput', false);
Display3D(CC, CR, X);
end
