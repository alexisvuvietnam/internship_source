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
// import "blocs/Transport_GIS.gaml"
import "blocs/Transport.gaml"
import "blocs/Urbanplanning.gaml"
import "blocs/Environnement.gaml"

/**
 * This is the main section of the simulation. Here, we instanciate our blocs, and launch the simulation through the coordinator.
 */
global {
// parameters for city generation
	int population_size <- 10000; // number of people in the simulation
	int number_of_mini_cities <- 100; // number of mini-cities
	int city_population <- 70000; // number of people per city (constellations of mini-cities)
	bool use_gis <- true; // use GIS or not (needed to spatialise, instanciate territory species, and to display the map)
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

	// Données pour chaque secteur

	// Surface
	float surface_used_agri <- 0.0;
	float surface_used_env <- 0.0;
	//	float surface_used_city <- 0.0;
	float surface_used_energy <- 0.0;

	// Eau
	float water_used_agri <- 0.0;
	float water_used_energy <- 0.0;
	//	float water_used_city <- 0.0;

	// Énergie
	float energy_used_agri <- 0.0;
	float energy_used_urban <- 0.0;
	float energy_used_transport <- 0.0;
	//	float energy_used_city <- 0.0;

	// GES émis
	float GES_emissions_agri <- 0.0;
	float GES_emissions_env <- 0.0;
	//	float GES_emissions_city <- 0.0;
	float GES_emissions_energy <- 0.0;
	float GES_emissions_urban <- 0.0;
	
	cities city_generator;

	init {
		if (use_gis) {
		// setup the territory :
			create fronteers from: shape_file_bounds;
			create mountain from: shape_mountains;
			create forest from: shape_file_forests;
			create water_source from: shape_rivers_lakes;
			// generation of the cities
			create cities number: 1 with:[
				shape_file_cities::shape_file_cities,
				city_population::city_population,
				number_of_mini_cities::number_of_mini_cities,
				population_size::population_size
			];
			ask cities {
				do generate_cities();
			}
		}

		// instanciate the blocs (E, A and R blocs here):
		create residents number: 1 {
			enabled <- enable_demography;
			nb_init_individuals <- population_size;
		}

		create agricultural number: 1 {
			pop_size <- population_size;
			prop_human <- round(7 * 1e7 / pop_size);
		}

		create energy number: 1;
		create urbanplanning number: 1;
		create transport number: 1;

		// L'environnement gère les mini-villes
		create environnement number: 1 {
			population <- population_size;
		}

		create coordinator number: 1;
		ask coordinator {
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
			species fronteers aspect: base;
			species mountain aspect: base transparency: 0.15;
			species forest aspect: base transparency: 0.15;
			species water_source aspect: base;
			species mini_city aspect: base;
			species main_city aspect: base;
		}
	}
}

experiment main_experiment type: gui {
//	float	total_emission <- world.tick_emissions_A["gCO2e emissions"] + world.tick_emissions_U["gCO2e emissions"] + world.tick_emissions_E["gCO2e emissions"] + world.tick_emissions_T["gCO2e emissions"] + world.tick_absorbed_ECO["gCO2e emissions"];
	parameter "Taille de la population :" var: population_size category: 'Model';
	//	parameter "Nombre de mini-villes :" var: number_of_mini_cities category: 'Model';
	//	parameter "Nombre d'individus par constellation de mini-villes:" var: city_population category: 'Model';	
	output {
	// Monitor des différentes valeurs
		monitor "Énergie consommée agriculture" value: world.tick_resources_used_A["kWh energy"];
		monitor "Énergie consommée urbanisme" value: world.tick_resources_used_U["kWh energy"];
		monitor "Énergie consommée transport" value: world.tick_resources_used_T["kWh energy"];
		monitor "Eau consommée agriculture" value: world.tick_resources_used_A["L water"];
		monitor "Eau consommée énergie" value: world.tick_resources_used_E["L water"];
		monitor "GES émis agriculture" value: world.tick_emissions_A["gCO2e emissions"];
		monitor "GES émis urbanisme" value: world.tick_emissions_U["gCO2e emissions"];
		monitor "GES émis énergie" value: world.tick_emissions_E["gCO2e emissions"];
		monitor "GES émis transport" value: world.tick_emissions_T["gCO2e emissions"];
		monitor "GES absorbés par l'environnement" value: world.tick_absorbed_ECO["gCO2e emissions"];
		monitor "Surface disponible totale" value: world.available_surface;

		// Affichage de la consommation d'énergie
		display "Répartition de la consommation d'énergie pour chaque secteur" type: 2d {
			chart "Consommation d'énergie pour chaque secteur" type: pie {
				data "Agriculture" value: world.tick_resources_used_A["kWh energy"] color: #orange;
				data "Urbanisme" value: world.tick_resources_used_U["kWh energy"] color: #gray;
				data "Transport" value: world.tick_resources_used_T["kWh energy"] color: #blue;
			}
		}

		display "Évolution de la consommation d'énergie pour chaque secteur" type: 2d {
			chart "Évolution de la consommation d'énergie pour chaque secteur" type: series {
				data "Agriculture" value: world.tick_resources_used_A["kWh energy"] color: #orange;
				data "Urbanisme" value: world.tick_resources_used_U["kWh energy"] color: #gray;
				data "Transport" value: world.tick_resources_used_T["kWh energy"] color: #blue;
			}
		}

		// Affichage de la consommation d'eau
		display "Répartition de la consommation d'eau pour chaque secteur" type: 2d {
			chart "Consommation d'eau pour chaque secteur" type: pie {
				data "Agriculture" value: world.tick_resources_used_A["L water"] color: #orange;
				data "Énergie" value: world.tick_resources_used_E["L water"] color: #yellow;
			}
		}

		display "Évolution de la consommation d'eau pour chaque secteur" type: 2d {
			chart "Évolution de la consommation d'eau pour chaque secteur" type: series {
				data "Agriculture" value: world.tick_resources_used_A["L water"] color: #orange;
				data "Énergie" value: world.tick_resources_used_E["L water"] color: #yellow;
			}
		}

		// Affichage des GES
		display "Répartition de la production de GES pour chaque secteur" type: 2d {
			chart "Quantité de GES émis pour chaque secteur (en grammes)" type: pie {
				data "Agriculture" value: world.tick_emissions_A["gCO2e emissions"] color: #orange;
				data "Urbanisme" value: world.tick_emissions_U["gCO2e emissions"] color: #gray;
				data "Energie" value: world.tick_emissions_E["gCO2e emissions"] color: #yellow;
			}
		}

		display "Évolution de l'émission de GES pour chaque secteur" type: 2d {
			chart "Évolution de l'émission de GES pour chaque secteur (en grammes)" type: series {
				data "Agriculture" value: world.tick_emissions_A["gCO2e emissions"] color: #orange;
				data "Urbanisme" value: world.tick_emissions_U["gCO2e emissions"] color: #gray;
				data "Energie" value: world.tick_emissions_E["gCO2e emissions"] color: #yellow;
				data "Transport" value: world.tick_emissions_T["gCO2e emissions"] color: #blue;
				data "Environnement" value: world.tick_absorbed_ECO["gCO2e emissions"] color: #green; // Ne s'affiche pas pour les données négatives
				data "Total" value:
				world.tick_emissions_A["gCO2e emissions"] + world.tick_emissions_U["gCO2e emissions"] + world.tick_emissions_E["gCO2e emissions"] + world.tick_emissions_T["gCO2e emissions"] + world.tick_absorbed_ECO["gCO2e emissions"]
				color: #black;
			}
		}
	}
}

