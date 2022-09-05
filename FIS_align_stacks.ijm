#@ String(value="<html>Register FIS timelapses to remove thermal drifts</html>", visibility="MESSAGE") msg1
#@ File (label = "Input folder", style = "directory") sourcefolder
#@ File (label = "Output folder", style = "directory") targetfolder
#@ Boolean (label = "Bleach correction?", value = false) correct_bleaching


//
//   Hugo M Botelho
//   hmbotelho@fc.ul.pt
//
//   Registration of FIS time lapses
//   v 0.1
//   05 Sept 2022
// 
//
//   Corrects thermal drifts in FIS images
//	 Requires htmrenamer processed images: https://github.com/hmbotelho/htmrenamer
//   Requires StackReg (BIG-EPFL update site): http://bigwww.epfl.ch/thevenaz/stackreg/
//   Supports multi channel datasets
//   Crops blank edges
//	 Optionally, applies bleach correction
//
//   Processed images are saved in a separate folder


// Initialize variables
setBatchMode(true);
regex = ".*C..\\.ome\\.tif$";
sourcefolder = replace(sourcefolder, "\\\\", "/");
targetfolder = replace(targetfolder, "\\\\", "/");
if(!endsWith(sourcefolder, "/")) sourcefolder = sourcefolder + "/";
if(!endsWith(targetfolder, "/")) targetfolder = targetfolder + "/";
close("*");
print("Starting stack alignment");
print("Source folder: " + sourcefolder);
print("Target folder: " + targetfolder);


// Find all image files
Table.create("file list");						// Initialize file table
listFilesRecursively(sourcefolder, regex);		// Populate file table
allfiles = Table.getColumn("path", "file list");
close("file list");


// Find all well+subposition combinations
wellpos = Array.copy(allfiles);
for(i=0; i<lengthOf(wellpos); i++){
	wellpos[i] = File.getDirectory(wellpos[i]);
}
wellpos = unique(wellpos);


// Process images
for(w=0; w<lengthOf(wellpos); w++){
	
	print("   Processing well " + wellpos[w]);
	wpfiles = getFileList(wellpos[w]);
	for(i=0; i<lengthOf(wpfiles); i++){
		wpfiles[i] = wellpos[w] + wpfiles[i];
	}
	
	// Find all available channels
	channels = Array.copy(wpfiles);
	for(i=0; i<lengthOf(channels); i++){
		channels[i] = replace(channels[i], "^.*--(C\\d\\d)\\.ome\\.tif$", "$1");
	}
	channels = unique(channels);
	
	
	// Process timelapses
	imgpath = wpfiles[0];
	for(c=0; c<lengthOf(channels); c++){
		
		// Initialize variables
		print("      channel " + c);
		path_source   = replace(imgpath, "--C...ome.tif$", "--" + channels[c] + ".ome.tif");
		path_target   = replace(path_source, sourcefolder, targetfolder);
		folder_source = File.getDirectory(imgpath);
		folder_target = File.getDirectory(path_target);
		
		// Get image names
		temp = getFileList(folder_source);
		fnames = newArray();
		for(i=0; i<lengthOf(temp); i++){
			if(endsWith(temp[i], "--" + channels[c] + ".ome.tif")){
				fnames = Array.concat(fnames, File.getName(temp[i]));
			}
		}
		
		// Open timelapse
		run("Image Sequence...", "dir=" + path_source + " filter=" + channels[c] + " sort");
		img_stack = getTitle();
		
	
		// Remove offset
			
			// Preprocess images
			// With RGB images (24 bit) StackReg sometimes generates a warning message which halts the macro. The message also occurs in interactive mode but does not halt code execution.
			// Converting to 8 bit solves this issue.
			if(bitDepth() == 24){
				run("Split Channels");
				close(img_stack + " (red)");
				close(img_stack + " (blue)");
				selectWindow(img_stack + " (green)");
				rename(img_stack);
				run("8-bit");
				setSlice(1);
				
				// Restore slice labels
				for (t=1; t<=nSlices; t++) {
					Property.setSliceLabel(fnames[t-1], t)	
				}
				
			}
			
			// Apply bleach correction
			// This sometimes improves registration accuracy.
			if(correct_bleaching){
				run("Bleach Correction", "correction=[Histogram Matching]");
				close(img_stack);
				selectWindow("DUP_" + img_stack);
				rename(img_stack);
			}

			// Align timelapse
			run("StackReg", "transformation=Translation");
			
			// Find the thickness of the black borders added during StackReg
			run("Z Project...", "projection=[Min Intensity]");
			borders = black_border_thickness();
			close();
					
			// Crop out image black borders
			selectWindow(img_stack);
			getDimensions(width1, height1, channels1, slices1, frames1);
			makeRectangle(borders[3], borders[0], width1-borders[1]-borders[3], height1-borders[0]- borders[2]);
			run("Crop");
			


		// Save images
		
			// Make sure the destination folder exists
			createDirRecursively(folder_target);
			
			// Save images
			run("Stack Splitter", "number=" + slices1);
			for(s1=0; s1<slices1; s1++){
				this_image = getTitle();
				saveAs("tiff", folder_target + this_image);
				close();
			}
		
		close(img_stack);
		
	}
	
}

print("The end");
waitForUser("Finished aligning stacks");





















//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////


function listFilesRecursively(folder, regex_fname) {

	tablename = "file list";
	
	// Check if file list table exists
	if(!isOpen(tablename)){
		Table.create(tablename);
	}

	list = getFileList(folder);

	for (i=0; i<list.length; i++) {

		path = "" + folder + list[i];
		path = replace(path, "\\\\", "/");

        if (endsWith(list[i], "/")){
        	// This is a folder
        	listFilesRecursively(path, regex_fname);

        } else{
        	// This is a file
 
        	if(matches(path, regex_fname)){

        		if(Table.headings() == ""){

					// Table has not entries yet
					files_before = newArray();
				} else {
					// Table already has something stored into it
					files_before = Table.getColumn("path", tablename);
           		}
           		files_after = Array.concat(files_before, path);
           		Table.setColumn("path", files_after, tablename);
           		Table.update;
        	}
        	
        }
     }
}



// Creates a folder, including any required parent folders
function createDirRecursively(path){

	if(File.exists(path) == false){
		
		// check if the parent folder exists
		parentfolder = File.getParent(path);
				
		if(File.exists(parentfolder)){
			if(isFilename(path) == false){
				File.makeDirectory(path);
							}
		} else{
			createDirRecursively(parentfolder);
		}

		if(isFilename(path) == false){
			File.makeDirectory(path);
		}
	}
}



// Tests whether a string is a file name
function isFilename(path){
	if(matches(path, "^(?:.)+\\.(?:.)+")){
		return(true);
	} else{
		return(false);
	}
}



// Eliminate duplicates from an array
function unique(array){

	output = newArray();
	
	for(i=0; i<array.length; i++){

		// Check if 'output' already contains this element
		inoutput = false;
		for(j=0; j<output.length; j++){
			if(array[i] == output[j]){
				inoutput = true;
			}
		}

		if(inoutput == false){
			output = Array.concat(output,array[i]);
		}
		
	}

	// output = Array.sort(output);
	return output;
}



// Measures the thicknesss of black borders in the active image
// Returns an array containing the Top, Right, Botton and Left borders, respectively.
function black_border_thickness() { 

	border = newArray(0,0,0,0);			// Top, Right, Botton, Left
	
	getDimensions(width, height, channels, slices, frames);
	
	// Top
	for(y=0; y<=height; y++){
		makeLine(0, y, width, y);
		profile = getProfile();
		run("Select None");
		Array.getStatistics(profile, min, max, mean, stdDev);
		if(min == 0 && max == 0){
			border[0] = y+1;
		} else{
			break;
		}
	}
	
	// Right
	for(x=width; x>=0; x--){
		makeLine(x, 0, x, height);
		profile = getProfile();
		run("Select None");
		Array.getStatistics(profile, min, max, mean, stdDev);
		if(min == 0 && max == 0){
			border[1] = width-x;
		} else{
			break;
		}
	}
	
	// Bottom
	for(y=height; y>=0; y--){
		makeLine(0, y, width, y);
		profile = getProfile();
		run("Select None");
		Array.getStatistics(profile, min, max, mean, stdDev);
		if(min == 0 && max == 0){
			border[2] = height-y;
		} else{
			break;
		}
	}
	
	// Left
	for(x=0; x<=width; x++){
		makeLine(x, 0, x, height);
		profile = getProfile();
		run("Select None");
		Array.getStatistics(profile, min, max, mean, stdDev);
		if(min == 0 && max == 0){
			border[3] = x+1;
		} else{
			break;
		}
	}
	
	return border;
}
