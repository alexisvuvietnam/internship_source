/**
* Name: Demography bloc (MOSIMA)
* Authors: Maël Franceschetti, Cédric Herpson, Jean-Daniel Kant
* Mail: firstname.lastname@lip6.fr
*/
model Demography

import "../API/API.gaml"

/**
 * We define here the global variables of the bloc. Some are needed for the displays (charts, series...).
 */
global {
/* Setup */
	int nb_ticks_per_year <- 12; // here, one tick is one month
	string female_gender <- "F";
	string male_gender <- "M";

	/* Input data (data for 2018, source : INSEE) */
	map<string, map<int, float>> init_age_distrib <- load_gender_data("../includes/data/init_age_distribution.csv"); // load initial ages distribution among the population for each gender
	map<string, map<int, float>> death_proba <- load_gender_data("../includes/data/death_probas.csv"); // load the probabilities to die in a year for each gender (per individual)
	map<string, map<int, float>> birth_proba <- load_gender_data("../includes/data/birth_probas.csv");
	map<string, float> init_gender_distrib <- [ // initial gender distribution in the population
	male_gender::0.4839825904115131, female_gender::0.516017409588487]; // ne need to use a csv file here, just two values

	/* Parameters */
	float coeff_birth <- 1.0; // a parameter that can be used to increase or decrease the birth probability
	float coeff_death <- 1.0; // a parameter that can be used to increase or decrease the death probability
	int nb_init_individuals <- 10000; // TODO : population initiale agrégée
	int nb_constellations <- 10; // TODO : constante fournie par le shapefile
	int nb_ind_per_constellations <- int(nb_init_individuals / nb_constellations);
	int nb_init_ind_per_mini_city <- int(nb_ind_per_constellations / 4); // TODO : paramètre à entrer pour l'utilisateur (pour l'instant 4 mini villes par constellations)

	/* Counters & Stats */
	int nb_inds -> {length(individual)};
	float births <- 0; // counter, accumulate the total number of births
	float deaths <- 0; // counter, accumulate the total number of deaths
	init {
	// a security added to avoid launching an experiment without the other blocs
		if (length(coordinator) = 0) {
			error "Coordinator agent not found. Ensure you launched the experiment from the Main model";
			// If you see this error when trying to run an experiment, this means the coordinator agent does not exist.
			// Ensure you launched the experiment from the Main model (and not from the bloc model containing the experiment).
		}

	}

	mini_city_demography mini_city_example; // Mini-ville exemple

	/* Load gender data (distribution, probabilities) per age category from a csv file */
	map<string, map<int, float>> load_gender_data (string filename) {
		file input_file <- csv_file(filename, ","); // load the csv file and separate the columns
		matrix data_matrix <- matrix(input_file); // put the data in a matrix
		map<int, float> male_data <- create_map(data_matrix column_at 0, data_matrix column_at 1); // create a map from male data
		map<int, float> female_data <- create_map(data_matrix column_at 0, data_matrix column_at 2); // same for female data
		map<string, map<int, float>> data <- [male_gender::male_data, female_gender::female_data]; // zip it in a all-in-one map
		return data; // return it
	}

}

/**
 * We define here the content of the demography (or "resident") bloc as a species.
 * We implement the methods of the API. Some are empty (do nothing) because this bloc do not have consumption nor production.
 * We also add methods specific to this bloc to handle the births and deaths in the population.
 */
species residents parent: bloc {
	string name <- "residents";
	bool enabled <- false; // true to activate the demography (births, deaths), else false.
	int total_population <- nb_init_individuals; // TODO : paramètre à entrer pour l'utilisateur
	int nb_ind_per_mini_city;
	int nb_mini_cities; // Nombre total de mini-villes
	list<string> population_needs <- ["kg_meat", "L water", "kg_vegetables"];

	// Liste de toutes les mini-villes
	list<mini_city_demography> mini_cities <- [];

	// Producteur pour accéder aux ressources des autres blocs
	demo_producer producer;

	/* setup the resident agent : initialize the population */
	action setup {

	// Initialisation du producer
		create demo_producer number: 1 returns: producers;
		producer <- first(producers);

		// Initialisation des mini-villes
		write "Population totale = " + total_population;
		write "Nombre de mini-villes = " + nb_mini_cities;
		nb_ind_per_mini_city <- int(total_population / nb_mini_cities);
		write "Nombre d'individus par mini-villes dans setup " + nb_ind_per_mini_city;
		do init_mini_cities;

		// Enregistrement de la mini-ville exemple
		mini_city_example <- mini_cities[0];
	}

	/* Initialisation des mini-villes */
	action init_mini_cities {
		create mini_city_demography number: nb_mini_cities {
		// write "Nombre d'individus par mini-ville dans init_mini_cities " + myself.nb_ind_per_mini_city;
			self.nb_individuals <- myself.nb_ind_per_mini_city;
			do init_population;

			// Enregistrement de la ville dans la liste des mini-villes
			myself.mini_cities <- myself.mini_cities + self;
		}

	}

	list<mini_city_demography> get_mini_cities {
		return mini_cities;
	}

	/* updates the population every tick */
	action tick (list<human> pop) {
		do collect_last_tick_data;
		if (enabled) {

		// Besoin total en viande
			float total_meat_need <- 0.0;

			// Besoin total en légumes
			float total_vegetables_need <- 0.0;

			// Besoin total en eau
			float total_water_need <- 0.0;

			// Parcourir toute les mini-villes
			ask mini_city_demography {

			// Capture les besoins en viande
				total_meat_need <- total_meat_need + self.population_meat_need();

				// Capture les besoins en légumes
				total_vegetables_need <- total_vegetables_need + self.population_vegetables_need();
			}

			do update_births;
			do update_deaths;
			do increment_age;
		}

	}

	list<string> get_input_resources_labels {
		return population_needs;
	}

	list<string> get_output_resources_labels {
		return []; // no resources for demography component (function declared only to respect bloc API)
	}

	production_agent get_producer {
		return nil; // no producer for demography component (function declared only to respect bloc API)
	}

	action collect_last_tick_data { // update stats & measures
		int nb_men <- individual count (not dead(each) and each.gender = male_gender);
		int nb_woman <- individual count (not dead(each)) - nb_men;
	}

	action set_external_producer (string product, production_agent prod_agent) {
	// no external producer for demography component (function declared only to respect bloc API)
	}

	/* apply births */
	action update_births {
		int new_births <- 0;
		ask individual {
			if (ticks_before_birthday <= 0) { // check only once a year for each individual
				if (gender = female_gender and flip(p_birth)) { // women can have children
					births <- births + 1;

					// Un nouveau individu naît (pas de jumeau)
					create individual number: 1 {

					// Il vit dans la même ville que sa mère
						self.my_city <- myself.my_city;

						// Ajouter l'individu à la liste des individus de la ville
						self.my_city.individuals <- self.my_city.individuals + self;
					}

				}

			}

		}

		//		int nb_f <- individual count (each.gender = female_gender and not (dead(each)));
		//		create individual number: new_births;
		//		births <- births + new_births;
	}

	/* apply deaths*/
	action update_deaths {
		ask individual {
			if (ticks_before_birthday <= 0) { // check only once a year for each individual
				if (flip(self.p_death)) { // every individual has a chance to die every month, or die by reaching max_age
					deaths <- deaths + 1;
					remove item: self from: self.my_city.individuals; // Supprimer l'individu de sa ville
					do die;
				}

			}

		}

	}

	/* increments the age of the individual if the tick corresponds to its birthday, and updates birth and death probabilities */
	action increment_age {
		ask individual {
			if (ticks_before_birthday <= 0) { // if the current tick is the individual birth date, increment the age
				age <- age + 1;
				ticks_before_birthday <- nb_ticks_per_year;
				do update_demog_probas; // update the death and birth probabilities
			} else {
				ticks_before_birthday <- ticks_before_birthday - 1;
			}

		}

	}

	/**
	 * Le bloc demography ne produit rien, mais on en a besoin pour récupérer les ressources des autres blocs
	  */
	species demo_producer parent: production_agent {
		map<string, bloc> external_producers; // external producers that provide the needed resources
		init {
			external_producers <- []; // external producers that provide the needed resources
		}

		/* Produce the given resources in the requested quantities. Return true in case of success. 
		 * buyer est l'entité qui demande, demand est un couple <ressource, quantité>. */
		bool produce (string buyer, map<string, float> demand) {
			return true;
		}

		/* Returns all the resources used for the production this tick */
		map<string, float> get_tick_inputs_used {
			return; // Pas utilisé par démographie
		}

		/* Returns the amounts produced this tick */
		map<string, float> get_tick_outputs_produced {
			return;
		}

		/* Returns the amounts emitted this tick */
		map<string, float> get_tick_emissions {
			return;
		}

		/* Defines an external producer for a resource */
		action set_supplier (string product, bloc bloc_agent) {
			write name + ": external producer " + bloc_agent + " set for " + product;
			external_producers[product] <- bloc_agent;
		}

	}

}

/**
 * We define the agents used in the demography bloc. We here extends the 'human' species of the API to add some functionalities.
 * Be careful to define features that will only be called within the demography block, in order to respect the API.
 * 
 * The demography of our population will here be based on death and birth probabilities.
 * These probabilities will depend on somme attributes of the individuals (age, gender ...).
 * We propose some formulas for these probabilities, based on INSEE data. These are rough estimates.
 */
species individual parent: human {
	float p_death <- 0.0;
	float p_birth <- 0.0;
	int ticks_before_birthday <- 0;
	int delay_next_child <- 0;
	int child <- 0;
	int nb_ind_real; // Nombre d'individus représentés réellement
	bool has_house; // Est-ce que l'individu possède un logement
	float meat_for_this_tick <- 0.0; // La quantité de viande que l'individu a mangé ce mois
	float vegetables_for_this_tick <- 0.0; // La quantité de légumes que l'individu a mangé ce mois
	mini_city_demography my_city; // Nom de la ville de l'agent

	// Stress annuel qui augmente la proba de mourir d'un individu si les besoins de ce dernier
	// ne sont pas répondus
	float yearly_stress <- 0.0;

	// Initialisation
	init {
		gender <- one_of([female_gender, male_gender]); // pick a gender randomly TODO : supprimer cette ligne
		ticks_before_birthday <- rnd(nb_ticks_per_year); // set a random birth date in the year (uniformly)
		// set initial birth & death probabilities :
		p_birth <- get_p_birth();
		p_death <- get_p_death();
	}

	/* returns the age category matching the age of the individual from a list */
	int get_age_category (list<int> ages_categories) {
		int age_cat <- max(ages_categories where (each <= age)); // get the last age category with a lower bound inferior to the age
		return age_cat;
	}

	/* Probabilités d'un individu de mourir.
	 * On suppose que le manque de nourriture n'influence que p_death.
	 */
	float get_p_death {
		int age_cat <- get_age_category(death_proba[gender].keys);
		float p <- death_proba[gender][age_cat];
		// p <- p * (1 + yearly_stress); Effet du logement et de l'alimentation
		return min(p, 1.0) * coeff_death;
	}

	/* Mise à jour du stress annuel */
	action update_monthly_stress {
		float stress <- 0.0;

		// Besoin en viande de l'individu
		float meat <- self.meat_for_this_tick / self.get_meat_need();

		// Besoin en légumes de l'individu
		float vegetables <- self.vegetables_for_this_tick / self.get_vegetables_need();

		// Besoin total en nourriture
		float food <- (meat + vegetables) / 2.0;

		// Est-ce que l'individu a une maison
		if (!has_house) {
			stress <- stress + 0.05;
		}

		// Influence des deux facteurs
		stress <- stress + (1 - food) * 0.1;
		yearly_stress <- yearly_stress + stress;
	}

	/* returns the probability for the individual to give birth this year */
	float get_p_birth {
		if (gender = male_gender) { // male don't give birth
			return 0.0;
		}

		int age_cat <- get_age_category(birth_proba[gender].keys);
		float p_birth <- birth_proba[gender][age_cat];
		return p_birth * coeff_birth;
	}

	/* updates birth and death probabilities of the individual */
	action update_demog_probas {
		p_birth <- get_p_birth();
		p_death <- get_p_death();
	}

	/* Besoin en viande d'un individu pour un  mois */
	float get_meat_need {
	// TODO à voir avec alimentation
		return 2.0;
	}

	/* Besoin en légumes d'un individu pour un mois */
	float get_vegetables_need {
	// TODO à voir avec alimentation
		return 15.0;
	}

}

species mini_city_demography parent: mini_city {

/*  Population de la mini-ville */
	int nb_individuals; // Nombre d'individus réels
	int factor_individuals <- 100; // Nombre d'individu représenté par un agent
	list<individual> individuals <- [];

	// Initialisation de la mini-ville
	init {
	// write "Nombre d'individu dans une mini-ville = " + nb_individuals;
		do init_population;
	}

	/* Initialisation de la population */
	action init_population {
		if nb_individuals <= 0 {
		// write "Nombre d'individu nul !";
		} else {
			int nb_agent_individuals <- int(nb_individuals / factor_individuals); // Le nombre d'agents
			create individual number: nb_agent_individuals {
				gender <- rnd_choice(init_gender_distrib); // override gender, pick a gender with respect to the real distribution
				age <- rnd_choice(init_age_distrib[gender]); // pick an initial age with respect to the real distribution and gender
				nb_ind_real <- myself.factor_individuals; // Le nombre d'individus que l'agent représente réellement
				myself.individuals <- myself.individuals + self; // Ajout de l'individu à la liste des individus de la mini-ville
				my_city <- myself;
				do update_demog_probas; // Mettre à jour les probas de naissance et de décès
			}

		}

	}

	/* --- Consommation de viande de la mini-ville. --- */

	/* Cette fonction retourne la quantité de viande en kg dont la population a besoin pour un mois. */
	float population_meat_need {
		float total_need <- 0.0;

		// Parcourir tous les individus
		loop ind over: self.individuals {
		// Récupérer les besoins d'un individu
			total_need <- total_need + ind.get_meat_need();
		}

		return total_need;
	}

	/* Cette fonction permet de nourrir la population de la ville de manière équitable entre tous les individus,
	 * selon les besoins de chacun. Si cette dernière n'est pas suffisante,
	 * la proba de mourir des individus augmente selon [TODO]. Retourne la nourriture en trop (nb négatif)
	 * ou en moins (positif). */
	float feed_population_meat (float meat_quantity) {
		float total_quantity <- meat_quantity;
		float diff <- total_quantity - self.population_meat_need(); // Nourriture en trop ou en moins

		// La quantité de viande est supérieure à ce qui est demandé
		if (diff < 0) {
		// Tronquer pour avoir la quantité adéquate
			total_quantity <- self.population_meat_need();
		}

		// Vérifier le pourcentage disponible
		float prop_meat <- total_quantity / self.population_meat_need();

		// Parcourir tous les individus
		loop ind over: self.individuals {

		// Récupérer les besoins de l'individu courant
			float need <- ind.get_meat_need();

			// Nourrir l'individu avec la quantité dispo proportionnellement à ses besoins
			ind.meat_for_this_tick <- need * prop_meat;
		}

		return diff;
	}

	/* --- Consommation de légumes de la mini-ville. --- */

	/* Cette fonction retourne la quantité de légumes en kg dont la population a besoin pour un mois. */
	float population_vegetables_need {
		float total_need <- 0.0;

		// Parcourir tous les individus
		loop ind over: self.individuals {
		// Récupérer les besoins d'un individu
			total_need <- total_need + ind.get_vegetables_need();
		}

		return total_need;
	}

	/* Cette fonction permet de nourrir la population de la ville de manière équitable entre tous les individus,
	 * selon les besoins de chacun. Si cette dernière n'est pas suffisante,
	 * la proba de mourir des individus augmente selon [TODO]. Retourne la nourriture en trop (nb négatif)
	 * ou en moins (positif). */
	float feed_population_vegetables (float vegetables_quantity) {
		float total_quantity <- vegetables_quantity;
		float diff <- total_quantity - self.population_vegetables_need(); // Nourriture en trop ou en moins

		// La quantité de légumes est supérieure à ce qui est demandé
		if (diff < 0) {
		// Tronquer pour avoir la quantité adéquate
			total_quantity <- self.population_vegetables_need();
		}

		// Vérifier le pourcentage disponible
		float prop_vegetables <- total_quantity / self.population_vegetables_need();

		// Parcourir tous les individus
		loop ind over: self.individuals {

		// Récupérer les besoins de l'individu courant
			float need <- ind.get_vegetables_need();

			// Nourrir l'individu avec la quantité dispo proportionnellement à ses besoins
			ind.vegetables_for_this_tick <- need * prop_vegetables;
		}

		return diff;
	}

	/* Loger la population */
	action population_housing {
	}

}

/**
 * We define here the experiment and the displays related to demography. 
 * We will then be able to run this experiment from the Main code of the simulation, with all the blocs connected.
 * 
 * Note : experiment car inherit another experiment, but we can't combine displays from multiple experiments at the same time. 
 * If needed, a new experiment combining all those displays should be added, for example in the Main code of the simulation.
 */
experiment run_demography type: gui {
	parameter "Initial number of individuals" var: nb_init_individuals min: 0 category: "Initialisation";
	parameter "Coefficient for birth probability" var: coeff_birth min: 0.0 max: 10.0 category: "Demography";
	parameter "Coefficient for death probability" var: coeff_death min: 0.0 max: 10.0 category: "Demography";
	parameter "Number of ticks per year" var: nb_ticks_per_year min: 1 category: "Simulation";
	output {
		display Population_information type: 2d {
			chart "Gender evolution" type: series size: {0.5, 0.5} position: {0, 0} {
				data "number_of_man" value: individual count (not dead(each) and each.gender = male_gender) color: #red;
				data "number_of_woman" value: individual count (not dead(each) and each.gender = female_gender) color: #blue;
				data "total_individuals" value: individual count (not dead(each)) color: #black;
			}

			chart "Age Pyramid" type: histogram background: #lightgray size: {0.5, 0.5} position: {0, 0.5} {
				data "]0;15]" value: individual count (not dead(each) and each.age <= 15) color: #blue;
				data "]15;30]" value: individual count (not dead(each) and (each.age > 15) and (each.age <= 30)) color: #blue;
				data "]30;45]" value: individual count (not dead(each) and (each.age > 30) and (each.age <= 45)) color: #blue;
				data "]45;60]" value: individual count (not dead(each) and (each.age > 45) and (each.age <= 60)) color: #blue;
				data "]60;75]" value: individual count (not dead(each) and (each.age > 60) and (each.age <= 75)) color: #blue;
				data "]75;90]" value: individual count (not dead(each) and (each.age > 75) and (each.age <= 90)) color: #blue;
				data "]90;105]" value: individual count (not dead(each) and (each.age > 90) and (each.age <= 105)) color: #blue;
			}

			chart "Births and deaths" type: series size: {0.5, 0.5} position: {0.5, 0} {
				data "number_of_births" value: births color: #green;
				data "number_of_deaths" value: deaths color: #black;
			}

		}

		monitor "Nombre de mini-villes" value: length(mini_city_demography);
		monitor "Nombre d'agents dans la mini ville exemple" value: length(mini_city_example.individuals);
	}

}

