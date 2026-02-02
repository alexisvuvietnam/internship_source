/**
* Name: Demography bloc (MOSIMA) - Aggregated Population Version
* Authors: Maël Franceschetti, Cédric Herpson, Jean-Daniel Kant
* Mail: firstname.lastname@lip6.fr
* 
* This version uses aggregated population counts at the city level instead of individual agents.
* Population is represented as integers with demographic distributions stored as maps.
*/

model Demography

import "../API/API.gaml"

/**
 * We define here the global variables of the bloc. Some are needed for the displays (charts, series...).
 */
global{
	/* Setup */ 
	int nb_ticks_per_year <- 12; // here, one tick is one month
	string female_gender <- "F";
	string male_gender <- "M";
	
	/* Input data (data for 2018, source : INSEE) */ 
	map<string, map<int, float>>  init_age_distrib <- load_gender_data("../includes/data/init_age_distribution.csv"); // load initial ages distribution among the population for each gender
	map<string, map<int, float>> death_proba <- load_gender_data("../includes/data/death_probas.csv"); // load the probabilities to die in a year for each gender (per individual)
	map<string, map<int, float>> birth_proba <- load_gender_data("../includes/data/birth_probas.csv");
	map<string, float> init_gender_distrib <- [ // initial gender distribution in the population
		male_gender ::0.4839825904115131, 
		female_gender ::0.516017409588487
	];
	
	/* Age categories for tracking population structure */
	list<int> age_categories <- [0, 6, 18, 67, 105];

	/* Parameters */ 
	float coeff_birth <- 1.0; // a parameter that can be used to increase or decrease the birth probability
	float coeff_death <- 1.0; // a parameter that can be used to increase or decrease the death probability
	
	/* Counters & Stats - Global aggregates */
	int total_population <- 0 update: sum(mini_city_demography collect each.pop);
	int total_males <- 0 update: sum(mini_city_demography collect each.males);
	int total_females <- 0 update: sum(mini_city_demography collect each.females);
	float total_births <- 0.0;
	float total_deaths <- 0.0;
	
	// Age pyramid data (aggregated from all cities)
	map<string, int> global_age_pyramid <- [];
	
	// tracks the current food shortage impact on mortality
	float shortage_mortality_factor <- 1.0; 
	
	init{  
		// a security added to avoid launching an experiment without the other blocs
		if (length(coordinator) = 0){
			error "Coordinator agent not found. Ensure you launched the experiment from the Main model";
		}
	}
	
	/* Load gender data (distribution, probabilities) per age category from a csv file */
	map<string, map<int, float>> load_gender_data(string filename){
		file input_file <- csv_file(filename, ",");
        matrix data_matrix <- matrix(input_file);
        map<int, float> male_data <- create_map(data_matrix column_at 0, data_matrix column_at 1);
        map<int, float> female_data <- create_map(data_matrix column_at 0, data_matrix column_at 2);
        map<string, map<int, float>> data <- [male_gender::male_data, female_gender::female_data];
        return data;
	}
	
	map<int, float> load_age_data(string filename) {
		file input_file <- csv_file(filename, ",");
		matrix data_matrix <- matrix(input_file);
		list<int> ages <- list<int>(data_matrix column_at 0);
		list<float> values <- list<float>(data_matrix column_at 1);
		map<int, float> result <- create_map(ages, values);
		return result;
	}
	
}


/**
 * Demography bloc using aggregated population counts.
 * No individual agents are created - population is tracked as integers at the city level.
 * Each mini_city maintains:
 * - Total population count
 * - Gender distribution
 * - Age distribution by category
 */
species residents parent:bloc{
	string name <- "residents";
	bool enabled <- false; // true to activate the demography (births, deaths), else false.
	
	// City-based demography information
	list<mini_city_demography> mini_cities <- [];
	list<main_city> main_cities <- [];
	
	int tick_counter <- 0; // Track ticks for annual updates
	
	action refresh_city_lists {
	    mini_cities <- list(mini_city_demography);
	    main_cities <- list(main_city);
	}
	
	/* setup the resident agent : initialize the population */
	action setup{
		do init_population_from_cities;
	}
	
	/* updates the population every tick */
	action tick(list<human> pop) {
	    if tick_counter = 0 {
	        do refresh_city_lists;
	        do setup;
	    }
	
	    tick_counter <- tick_counter + 1;
	
	    if enabled {
	        if tick_counter >= nb_ticks_per_year {
	            ask mini_cities {
	                do apply_births;
	                do apply_deaths;
	                do age_population;
	            }
	            tick_counter <- 0;
	        }
	    }
	
	    do collect_statistics;
	}


	
	list<string> get_input_resources_labels{ 
		return [];
	}
	
	list<string> get_output_resources_labels{
		return [];
	}
	
	production_agent get_producer{
		return nil;
	}
	
	action collect_last_tick_data{ // update stats & measures
		int nb_men <- individual count(not dead(each) and each.gender = male_gender);
		int nb_woman <-  individual count(not dead(each)) - nb_men;
		
		// Update shortage mortality factor
		float total_shortage_coeff <- 0.0;
		int count_with_coeff <- 0;
		ask individual where (not dead(each)) {
			if (additional_attributes contains_key "shortage_mortality_coeff") {
				total_shortage_coeff <- total_shortage_coeff + float(additional_attributes["shortage_mortality_coeff"]);
				count_with_coeff <- count_with_coeff + 1;
				
			}
		}
		if (count_with_coeff > 0) {
			shortage_mortality_factor <- total_shortage_coeff / count_with_coeff;
		} else {
			shortage_mortality_factor <- 1.0;
		}
	}
	
	action population_activity(list<human> pop){
		 // no population activity for demography component (function declared only to respect bloc API)
	}
	
	action set_external_producer(string product, production_agent prod_agent){
		// no external producer for demography component (function declared only to respect bloc API)
	}
	
	/* initialize the population */
	action init_population{
		create individual number:nb_init_individuals{
			gender <- rnd_choice(init_gender_distrib); // override gender, pick a gender with respect to the real distribution
			age <- rnd_choice(init_age_distrib[gender]);  // pick an initial age with respect to the real distribution and gender
			do update_demog_probas;
		}
		
		// Aggregate age pyramid
		global_age_pyramid <- [];
		loop age_cat over: age_categories {
			string key <- "]" + (age_cat - 15) + ";" + age_cat + "]";
			if age_cat = 0 {
				key <- "]0;15]";
			}
			int count <- sum(mini_cities collect (each.age_distribution[age_cat]));
			global_age_pyramid[key] <- count;
		}
	}
	
	/* Initialize population in each mini_city based on demographic distributions */
	action init_population_from_cities{
		if empty(mini_cities) {
			write "ERREUR: mini_cities est vide, aucune population ne sera créer.";
			return;
		}
		
		ask mini_cities {
			do initialize_demographics;
		}
	}
	
	/*
	 * Get the current total population size.
	 * Other blocs can call this to get the current population count.
	 */
	int get_total_population {
		return total_population;
	}
	
	/*
	 * Get the list of mini_cities with current population data.
	 * Other blocs can use this to access city-specific population information.
	 */
	list<mini_city> get_mini_cities_with_population {
		return mini_cities;
	}
}

/**
 * Extended mini_city species with demographic tracking.
 * Each mini_city maintains aggregated population data without creating individual agents.
 */
species mini_city_demography parent: mini_city {
	// Demographic attributes
	string female_gender;
	string male_gender;
	int males <- 0;
	int females <- 0;
	int go_to_school;
	int go_to_work;
	
	// age distribution: map from age category to count
	map<int, int> age_distribution <- [];
	
	// gender-specific age distributions
	map<string, map<int, int>> gender_age_distribution;
	
	// tracking for statistics
	float births_this_year <- 0.0;
	float deaths_this_year <- 0.0;
	
	/**
	 * initialize demographic structure based on population size and distributions
	 */
	action initialize_demographics {
	    male_gender <- "M";
	    female_gender <- "F";
			
		males <- int(pop * init_gender_distrib[male_gender]);
	    females <- pop - males;
	
	    if (gender_age_distribution = nil) {
	        gender_age_distribution <- [];
	    }
	
	    if (age_distribution = nil) {
	        age_distribution <- [];
	    }
	
	    loop gender over: [male_gender, female_gender] {
	
	        int gender_pop <- (gender = male_gender) ? males : females;
	        map<int, float> age_probs <- init_age_distrib[gender];
	
	        if (age_probs = nil) {
	            write "ERREUR: Distribution des ages manquante " + gender;
	            continue;
	        }
	
	        if (gender_age_distribution[gender] = nil) {
	            gender_age_distribution[gender] <- [];
	        }
	
	        loop i from: 0 to: length(age_categories) - 1 {
	
	            int age_cat <- age_categories[i];
	            float proportion <- age_probs[age_cat];
	            int count <- int(gender_pop * proportion);
	
	            gender_age_distribution[gender][age_cat] <- count;
	
	            if (age_distribution[age_cat] = nil) {
	                age_distribution[age_cat] <- 0;
	            }
	
	            age_distribution[age_cat] <- age_distribution[age_cat] + count;
	        }
	    }
	    
	    go_to_school <- put_category(18);
	    go_to_work <- put_category(67);
	    
	}

	
	/* returns the age category matching the age of the individual from a list */
	int get_age_category(list<int> ages_categories){
		int age_cat <- max(ages_categories where (each <= age)); // get the last age category with a lower bound inferior to the age
		return age_cat;
	}
	
	/* returns the probability for the individual to die this year + add food shortage coeff */
	float get_p_death{ // compute monthly death probability of an individual
		int age_cat <- get_age_category(death_proba[gender].keys);
		//float p_death <-  death_proba[gender][age_cat];
		//return  p_death * coeff_death;
		float base_p_death <-  death_proba[gender][age_cat];

		float shortage_coeff <- 1.0;
		if (additional_attributes contains_key "shortage_mortality_coeff") {
			shortage_coeff <- float(additional_attributes["shortage_mortality_coeff"]);
		}
		
		float new_p_death <- min([base_p_death * coeff_death * shortage_coeff,1.0]);
		if shortage_coeff > 1.0{
			if(flip(p_death)){ // every individual has a chance to die every month, or die by reaching max_age
					deaths <- deaths +1;
					do die;
		}
		}
		
		return new_p_death;
	}
	
	/* returns the probability for the individual to give birth this year */
	float get_p_birth{
		if(gender = male_gender){ // male don't give birth
			return 0.0;
		}
	}
	
	/**
	 * Apply deaths based on age-specific mortality rates
	 */
	action apply_deaths {
		float expected_deaths <- 0.0;
		map<int, int> male_age_map <- age_categories as_map (each::0);
		map<int, int> female_age_map <- age_categories as_map (each::0);
		map<string, map<int, int>> deaths_by_gender_age <- [
			male_gender :: male_age_map,
			female_gender :: female_age_map
		];
		
		// calculate deaths for each gender and age category
		loop gender over: [male_gender, female_gender] {
			loop age_cat over: age_categories {
				int count <- gender_age_distribution[gender][age_cat];
				if count > 0 {
					float death_prob <- death_proba[gender][age_cat];
					death_prob <- death_prob * coeff_death;
					
					float expected <- count * death_prob;
					int deaths <- int(expected) + (flip(expected - int(expected)) ? 1 : 0);
					deaths <- min([deaths, count]); // Can't exceed population in category
					
					deaths_by_gender_age[gender][age_cat] <- deaths;
					expected_deaths <- expected_deaths + deaths;
				}
			}
		}
		
		// apply deaths
		loop gender over: [male_gender, female_gender] {
			loop age_cat over: age_categories {
				int deaths <- deaths_by_gender_age[gender][age_cat];
				if deaths > 0 {
					gender_age_distribution[gender][age_cat] <- gender_age_distribution[gender][age_cat] - deaths;
					age_distribution[age_cat] <- age_distribution[age_cat] - deaths;
					
					if gender = male_gender {
						males <- males - deaths;
					} else {
						females <- females - deaths;
					}
					
					pop <- pop - deaths;
					deaths_this_year <- deaths_this_year + deaths;
				}
			}
		}
	}
	
	/**
	 * Age the population by moving people to next age categories
	 */
	action age_population {
		// create new age distributions
		map<int, int> new_age_distribution <- [];
		map<int, int> male_age_map <- age_categories as_map (each::0);
		map<int, int> female_age_map <- age_categories as_map (each::0);
		map<string, map<int, int>> new_gender_age_distribution <- [
			male_gender :: male_age_map,
			female_gender :: female_age_map
		];
		
		// age each cohort
		loop gender over: [male_gender, female_gender] {
			loop i from: 0 to: length(age_categories) - 1 {
				int current_age <- age_categories[i];
				int count <- gender_age_distribution[gender][current_age];
				
				if count > 0 {
					// move to next age category (or stay in last one)
					int next_age <- current_age;
					if i < length(age_categories) - 1 {
						next_age <- age_categories[i + 1];
					}
					
					new_gender_age_distribution[gender][next_age] <- (new_gender_age_distribution[gender][next_age]) + count;
					new_age_distribution[next_age] <- (new_age_distribution[next_age]) + count;
				}
			}
		}
		
		// Update distributions
		age_distribution <- new_age_distribution;
		gender_age_distribution <- new_gender_age_distribution;
	    go_to_school <- put_category(18);
	    go_to_work <- put_category(67);
	}
	
	int put_category(int age_category){
		return int(pop * age_distribution[age_category]);
	}
	
	// --- GIS
	
	aspect population {
		rgb pop_color <- rgb(min([255, pop / 100]), 100, 100);
		draw circle(radius) color: pop_color border: #black;
		//draw sting(pop) color: #black size: 12 at: location;
	}
}
/**
 * Experiment for demography visualization with aggregated population
 */
experiment run_demography type: gui {
	parameter "Coefficient for birth probability" var: coeff_birth min: 0.0 max: 10.0 category: "Demography";
	parameter "Coefficient for death probability" var: coeff_death min: 0.0 max: 10.0 category: "Demography";
	parameter "Number of ticks per year" var: nb_ticks_per_year min:1 category: "Simulation";

	output {
		display Population_information {
			chart "Gender evolution" type: series size: {0.5,0.5} position: {0, 0} {
				data "Males" value: total_males color: #red;
				data "Females" value: total_females color: #blue;
				data "Total population" value: total_population color: #black;
			}
			
			chart "Births and deaths" type: series size: {0.5,0.5} position: {0.5, 0} {
				data "Births" value: total_births color: #green;
				data "Deaths" value: total_deaths color: #red;
				data "Net change" value: total_births - total_deaths color: #black;
			}
		}
	}
}