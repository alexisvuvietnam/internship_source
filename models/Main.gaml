/**
* Name: Main (MOSIMA)
* Authors: Maël Franceschetti, Cédric Herpson, Jean-Daniel Kant
* Mail: firstname.lastname@lip6.fr
*/

model Main

import "API/API.gaml"
import "blocs/Demography.gaml"
import "blocs/Agricultural.gaml"
import "blocs/Energy.gaml"
import "blocs/Transport.gaml"
import "blocs/Urbanplanning.gaml"
import "blocs/Ecosystem.gaml"

/**
 * This is the main section of the simulation. Here, we instanciate our blocs, and launch the simulation through the coordinator.
 */
global{
	// parameters for city generation
	int population_size <- 1000000; // number of people in the simulation
	int number_of_mini_cities <- 100; // number of mini-cities
	int city_population <- 70000; // number of people per city (constellations of mini-cities)
	
	bool use_gis <- false; // use GIS or not (needed to spatialise, instanciate territory species, and to display the map)
	float step <- 1 #month; // the simulation step is a month
	bool enable_demography <- true; // true to activate the demography (births, deaths), else false
	
	// GIS files
	file shape_file_cities <- file("../includes/shapefiles/cities_france.shp");
	file shape_file_bounds <- file("../includes/shapefiles/boundaries_france.shp");
	file shape_file_forests <- file("../includes/shapefiles/forests_france_light.shp");
	file shape_rivers_lakes <- file("../includes/shapefiles/rivers_france_light.shp");
	file shape_mountains <- file("../includes/shapefiles/mountains_france_1300m.shp");
	geometry shape <- envelope(shape_file_bounds);
	geometry shape_cities <- envelope(shape_file_cities);
	
	init{
		if(use_gis){
			// setup the territory :
			create fronteers from: shape_file_bounds;
			create mountain from: shape_mountains;
			create forest from: shape_file_forests;
			create water_source from: shape_rivers_lakes;
			
			create cities with: [
				population_size::population_size,
				number_of_mini_cities::number_of_mini_cities,
				city_population::city_population,
				shape_file_cities::shape_file_cities,
				shape::shape_cities
			];
			// get the list of all the main cities and mini-cities
			list<mini_city> all_mini_cities <- [];
			list<main_city> all_main_cities <- [];
			
			// get the cities agent (there is only one)
			if !empty(cities) {
				all_mini_cities <- first(cities).get_mini_cities();
				all_main_cities <- first(cities).get_main_cities();
			}
			write "Total de mini-villes créées: " + length(all_mini_cities);
			write "Total de villes créées: " + length(all_main_cities);
		}
		
		// instanciate the blocs (E, A and R blocs here):
		create residents number:1{
			enabled <- enable_demography;
		}
		create agricultural number:1;
		create energy number:1;
		create urbanplanning number:1;
		create transport number:1;
		create ecosystem number:1;
		create coordinator number:1;
		
		ask coordinator{
			do register_all_blocs;
			do start;
		}
	}
}

/**
 * We define only one experiment in the main file : the display of the GIS. 
 * Other displays are defined in the blocs experiments.
 */
experiment display_gis type: gui {
	parameter "Taille de la population :" var: population_size category: 'Model';
	parameter "Nombre de mini-villes :" var: number_of_mini_cities category: 'Model';
	parameter "Nombre d'individus par constellation de mini-villes:" var: city_population category: 'Model';
	
	output {
		display country_map type: java2D {
			species fronteers aspect: base ;
			species mountain aspect: base transparency: 0.15;
			species forest aspect: base transparency: 0.15;
			species water_source aspect: base ;
			// species city aspect: base ;
			species main_city aspect: default;
			species mini_city aspect: default;
		}
	}
}

