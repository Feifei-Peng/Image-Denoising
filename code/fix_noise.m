function fix_noise()
    %init table
    data = table;
    
    %remove previous observations
    warning off;
    delete 'data.csv';
    warning on;
    
    %find folders containing the noisy images
    d = dir('noisy');
    isub = [d(:).isdir]; 
    nameFolds = {d(isub).name}';
    nameFolds(ismember(nameFolds,{'.','..'})) = [];
    
    %loop over the provided images;
    for im_folder = nameFolds(:)'
        im_folder = [im_folder{1} '/'];
        
        %remove previous observations
        [~] = rmdir(['fft_freq/' im_folder], 's');
        [~] = rmdir(['fft_conv/' im_folder], 's');
        [~] = rmdir(['freq_conv/' im_folder], 's');
        [~] = rmdir(['conv_freq/' im_folder], 's');
        [~] = rmdir(['wiener/' im_folder], 's');
        [~] = rmdir(['fft_r/' im_folder], 's');
        [~] = rmdir(['fft_c/' im_folder], 's');
        [~] = rmdir(['dct_r/' im_folder], 's');
        [~] = rmdir(['dct_c/' im_folder], 's');
        
        %init new observations
        mkdir(['fft_conv/' im_folder 'before'])
        mkdir(['fft_conv/' im_folder 'after'])
        mkdir(['fft_freq/' im_folder 'before'])
        mkdir(['fft_freq/' im_folder 'after'])
        mkdir(['freq_conv/' im_folder 'conv/before'])
        mkdir(['freq_conv/' im_folder 'conv/after'])
        mkdir(['freq_conv/' im_folder 'freq/before'])
        mkdir(['freq_conv/' im_folder 'freq/after'])
        mkdir(['conv_freq/' im_folder 'conv/before'])
        mkdir(['conv_freq/' im_folder 'conv/after'])
        mkdir(['conv_freq/' im_folder 'freq/before'])
        mkdir(['conv_freq/' im_folder 'freq/after'])
        mkdir(['wiener/' im_folder])
        mkdir(['fft_r/' im_folder])
        mkdir(['fft_c/' im_folder])
        mkdir(['dct_r/' im_folder])
        mkdir(['dct_c/' im_folder])

        %read files and original for reference
        files = dir(['noisy/' im_folder '*.png']);
        original = ['noisy/' im_folder '0_original.png'];
        originalImage = imread(original);

        %store the implemented algorithms in a functional way
        spectrum = @(image, name, layer, folder) fft_denoise(image, name, layer, folder);
        convolution = @(image, name, layer, folder) filter(image, name, layer, folder);
        both = @(image, name, layer, folder) convolution(...
            spectrum(image, name, layer, [folder 'freq/']),...
            name, layer, [folder 'conv/']);
        both_r = @(image, name, layer, folder) spectrum(...
            convolution(image, name, layer, [folder 'conv/']),...
            name, layer, [folder 'freq/']);
        filt = @(image, name, layer, folder) matlab_filter(image, name, layer, folder);
        four_row = @(image,name,layer,folder) fft_r(image, name, layer, folder);
        four_col = @(image,name,layer,folder) fft_c(image, name, layer, folder);
        dct_row = @(image,name,layer,folder) dct_r(image, name, layer, folder);
        dct_col = @(image,name,layer,folder) dct_c(image, name, layer, folder);
        
        %store al iteration specific information in cell arrays
        functions = {convolution, spectrum, both, both_r, filt, four_row, four_col, dct_row, dct_col};
        names = {'Convolution filter', 'Spectrum filter',...
            'First spectrum then convolution',...
            'First convolution then spectrum', 'Wiener Filter', 'FFT row', 'FFT col', 'DCT row', 'DCT col'};
        folders = {'fft_conv/', 'fft_freq/', 'freq_conv/', 'conv_freq/', 'wiener/', 'fft_r/', 'fft_c/', 'dct_r/', 'dct_c/'};

        %prepare_folders();
        
        %loop over files and remove noise
        for f = files(:)'
            file = f.name;

            %read the current image file
            imageFile = imread(['noisy/' im_folder file]);

            %calculate both metrics on the noisy file
            [oldPeak, ~] = psnr(imageFile, originalImage);
            oldSsim = ssim(imageFile, originalImage);

            %check how many layers the file has (1 = grey, 3 = rgb)
            [~, ~, colors] = size(imageFile);
            
            %apply every denoising funtion to the file
            for i = 1:length(functions)
                
                func = functions{i};
                
                %init the result for faster performance
                transformed = uint8(zeros(size(imageFile)));
                
                %apply the transformation to every image layer and measure
                %time passed
                tic
                for n = 1:colors
                   transformed(:, :, n) = func(imageFile(:, :, n), file,...
                       n, [folders{i} im_folder]);
                end
                timer = toc;
                
                % Save the image
                newName = [folders{i} im_folder file];
                imwrite(transformed, newName);

                % Reload the image to make sure the numbers are loaded in 
                % the same format as the original image. 
                transformed = imread(newName);

                %calculate the new metrics
                [newPeak, ~] = psnr(transformed, originalImage);
                newSsim = ssim(transformed, originalImage);

                %save information
                if(~(oldPeak == Inf))
                    data = [data; {im_folder, file, names{i}, timer, 'PSNR',...
                        oldPeak, newPeak, (newPeak-oldPeak)}];
                end
                data = [data; {im_folder, file, names{i}, timer, 'SSIM',...
                    oldSsim, newSsim, (newSsim-oldSsim)}];
            end
        end
    end
    
    %name headers and save to csv
    data.Properties.VariableNames = {'bestand','noise','algoritme','tijd',...
        'metriek', 'voor', 'na', 'verschil'};
    writetable(data, 'data.csv');
end

function out = matlab_filter(imageFile, name, layer, folder)
% Use the built in wiener filter which denoises images, to compare the
% implemented algorithms to.

    out = wiener2(imageFile, [5 5]);
end

function out = filter(imageFile, name, layer, folder)
% Use convolution with a gaussian kernel to smooth out any noise. This will
% reduce the sharpness of the image, and blurriness may occur.
%
% imageFile:    the nxn matrix representing the image to denoise
% name:         name of the output file
% dim:          the current color dimension of the image (for storage
%               purposes)
% folder:       name of the folder where additional image can be stored
    
    % measure image dimensions and convert it to double
    [len, ~] = size(imageFile);
    imageFile = im2double(imageFile);
    
    % initialise a 3x3 gaussian convolution kernel
    g = fspecial('gaussian', [3 3], 5);
    
    % calculate al edges so we can transform the 3x3 kernel to an lenxlen
    % kernel that is identical when we fft it
    c = g(2:3,2:3);
    ur = g(1, 2:3);
    ul = g(1,1);
    l = g(2:3,1);
    
    %rotary transform the kernel so the center lies on the top left and pad
    %the center bits of the matrix with 0's
    center = zeros(len, len-2-1);
    
    %left part
    left_center = zeros(len-2-1, 2);
    left = [c;left_center;ur];
    
    %right part
    right_center = zeros(len-2-1 ,1);
    right = [l; right_center; ul];
    
    %the lenxlen kernel equivalent with the 3x3 kernel
    kernel = [left center right];
    
    %apply fft to both matrices
    image_fft = fft2(imageFile);
    g_fft = fft2(kernel);
  
    %calculate the convolution of the kernel and the image. Because we are
    %in the fft domain this is equivalent with the point-wise
    %multiplication of both matrices.
    out = uint8(255*ifft2(image_fft.*g_fft));
    
    % Convert dimension to string
    dim = char(strcat('_', string(layer)));
    
    % File name.
    name = strsplit(name, '.');
    name = name{1};
    
    %write out the fft spectrums before and after convolution
    imwrite(uint8(20*log(abs(fftshift(image_fft)))), [folder 'before/' name dim '.png']);
    imwrite(uint8(20*log(abs(fftshift(image_fft.*g_fft)))), [folder 'after/' name dim '.png']);
end

function image = fft_denoise(imageFile, name, dim, folder)
% Try to denoise the image by converting it to its spatial domain and
% zeroing out peak values where they are not to be expected. This function
% makes use of the spatial locality of information arounde the center in
% the 2-D fourier domain. This will be the most usefull for images with
% noise that follows a predictable pattern, because this noisy pattern will
% be clearly visible in the amplitude domain.
%
% imageFile:    the nxn matrix representing the image to denoise
% name:         name of the output file
% dim:          the current color dimension of the image (for storage
%               purposes)
% folder:       name of the folder where additional image can be stored

    % FFT transfrom the data, then shift it's DC (0 frequency) component to
    % the center of the spectrum.
    spectrum = fftshift(fft2(imageFile));
    
    % Take the abs of the DFT to find the magnitude of the wave. Take the 
    % log of the DFT to enlarge values around 0 (where most of the
    % values lie) and make them more visible. Multiply this by 20 to find
    % the orders of magnitude (dB).
    amplitude = 20*log(abs(spectrum));
    
    % Remove the noise from the image using the noise function. Then return
    % to the original image format by inverting the DFT and the spectrum
    % shift.
    im = uint8(ifft2(fftshift(...
        remove_noise(spectrum, amplitude, name, dim, folder)...
        )));
    
    image = im;
end

function image = remove_noise(spectrum, amplitude, name, dim, folder)
% Try to remove the noise from an image, given its DFT. We will achieve
% this by removing peak values that are not around the center of the
% spectrum.
%
% spectrum:     The spectrum of the DFT of the image.
% amplitude:    The amplitude of that spectrum, we will use this amplitude to
%               cut-off certain frequencies (zero them out).
% peak:         The value to be considered a peak in the amplitude
%               spectrum.
% tolerance:    The radius of peaks allowed around the center of the
%               spectrum to allow for the original image to be retained.
% name:         Name of the output files.
    
    % Default values.
    if(isempty(dim))
        dim = 1;
    end
    
    % Convert dimension to string
    dim = char(strcat('_', string(dim)));
    
    % File name.
    name = strsplit(name, '.');
    name = name{1};
    
    % Write the amplitude image before the transformation to a file.
    imwrite(uint8(amplitude), [folder 'before/' name dim '.png']);
    
    % Calculate the dimensions of the image/amplitude matrix.
    n = size(amplitude)/2;
    n = n(1);
    
    %Estimate the peak and tolerance
    peak = mean(amplitude(:)) + 1.5*std(amplitude(:));
    tolerance = n/5;
    
    % Pick the cut-off frequencies
    peakimage = amplitude > peak;
    
    % Calculate the mean and std around the center
    middle = amplitude(n:n+1, n:n+1);
    range = mean(middle(:));
    stdv = std(middle(:));
    minRange = range - stdv;
    maxRange = range + stdv;
    
    % Calculate the radius
    u_center = amplitude > minRange;
    l_center = amplitude < maxRange;
    center = u_center & l_center;
    lower = n - tolerance;
    upper = n + tolerance;
    [x,y] = size(amplitude);
    
    % Ignore peaks in the radius around the center.
    for i = 1:x
        xI = i;
        for j = 1:y
            yI = j;
            if(xI <= upper && xI >= lower && yI <= upper && yI >= lower)
                peakimage(xI,yI) = 0;
            end
        end
    end
    
    % Zero out the peaks in the spectrum and amplitude domain.
    spectrum(peakimage) = 0 + 0i;
    amplitude(peakimage) = 0;
    
    % Write out the amplitude image after the transformation.
    imwrite(uint8(amplitude), [folder 'after/' name dim '.png']);
    
    % Return the modified spectrum.
    image = spectrum;
end

function row = matrix_as_row(A)
    row = reshape(A.',1,[]);
end

function matrix = row_as_matrix(A,n)
    matrix = vec2mat(A,n);
end

function col = matrix_as_col(A)
    col = A(:)';
end

function matrix = col_as_matrix(A,n)
    matrix = reshape(A,n,[]);
end

function image = fft_r(imageFile, name, layer, folder)
    [n, ~] = size(imageFile);
    image = uint8(real(ifft2(row_as_matrix(fft(matrix_as_row(imageFile)), n))))';
end

function image = fft_c(imageFile, name, layer, folder)
    [n, ~] = size(imageFile);
    image = uint8(real(ifft2(col_as_matrix(fft(matrix_as_col(imageFile)), n))))';
end

function image = dct_r(imageFile, name, layer, folder)
    imageFile = im2double(imageFile);
    [n, ~] = size(imageFile);
    image = uint8(255*real(idct2(row_as_matrix(dct(matrix_as_row(imageFile)), n))))';
end

function image = dct_c(imageFile, name, layer, folder)
    imageFile = im2double(imageFile);
    [n, ~] = size(imageFile);
    image = uint8(255*real(idct2(col_as_matrix(dct(matrix_as_col(imageFile)), n))))';
end