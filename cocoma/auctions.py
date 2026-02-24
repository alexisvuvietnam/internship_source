from objects import Instance, ScheduledTask, Task
from planning import schedule_tasks_for_satellite, marginal_cost_of_task_on_satellite, build_task_index
from typing import List, Dict
from math import inf

def build_initial_schedules_for_auctions(instance, mode="flexibility"):
    """
    Construit l'état initial des enchères :
    - planifie les tâches des utilisateurs exclusifs sur leur satellite (si satellite a un exclusive_user_id)
    - prépare un mapping sat_id -> liste d'IDs de tâches déjà affectées (exclusifs)
    - prépare un mapping sat_id -> schedule (liste de ScheduledTask) correspondant au planning initial

    Retour:
      sat_to_tasks_ids: dict[sat_id] -> list[task_id]
      sat_to_schedule:  dict[sat_id] -> list[ScheduledTask]
    """
    sat_to_tasks_ids = {}
    sat_to_schedule = {}

    for sat in instance.satellites:
        if sat.exclusive_user_id is None:
            exclusive_tasks = []
        else:
            exclusive_tasks = [t for t in instance.tasks if t.user_id == sat.exclusive_user_id]

        sched = schedule_tasks_for_satellite(
            satellite=sat,
            tasks=exclusive_tasks,
            horizon=instance.horizon,
            mode=mode
        )

        sat_to_tasks_ids[sat.id] = [st.task_id for st in sched]
        sat_to_schedule[sat.id] = sched

    return sat_to_tasks_ids, sat_to_schedule

def psi_auction(
    instance: Instance,
    mode: str = "flexibility"
) -> Dict[int, List[ScheduledTask]]:
    """
    Enchères PSI : allocation parallèle des tâches standards.

    Idée générale :
    - on part du planning contenant uniquement les tâches exclusives,
    - chaque tâche standard regarde sur quel satellite elle "coûte" le moins,
    - on assigne toutes les tâches gagnantes en même temps,
    - on met à jour les plannings,
    - on recommence jusqu'à ce qu’on ne puisse plus rien ajouter.
    """

    sat_to_tasks_ids, sat_to_schedule = build_initial_schedules_for_auctions(instance, mode)

    task_index = build_task_index(instance)

    standard_users = set(instance.standard_users)

    already_scheduled = set(t_id for lst in sat_to_tasks_ids.values() for t_id in lst)

    unallocated_tasks = [
        t for t in instance.tasks
        if t.user_id in standard_users and t.id not in already_scheduled
    ]

    changed = True

    while changed and unallocated_tasks:
        changed = False
        new_assignments = []

        for task in unallocated_tasks:
            best_sat_id = None
            best_cost = inf

            for sat in instance.satellites:
                current_ids = sat_to_tasks_ids.get(sat.id, [])

                mc = marginal_cost_of_task_on_satellite(
                    instance=instance,
                    task=task,
                    sat=sat,
                    sat_current_tasks_ids=current_ids,
                    task_index=task_index,
                    mode=mode
                )

                if mc < best_cost:
                    best_cost = mc
                    best_sat_id = sat.id

            if best_sat_id is not None and best_cost < inf:
                new_assignments.append((task, best_sat_id))

        if not new_assignments:
            break

        for task, sat_id in new_assignments:
            sat_to_tasks_ids[sat_id].append(task.id)

        for sat in instance.satellites:
            current_ids = sat_to_tasks_ids[sat.id]
            current_tasks = [task_index[t_id] for t_id in current_ids]

            sat_to_schedule[sat.id] = schedule_tasks_for_satellite(
                satellite=sat,
                tasks=current_tasks,
                horizon=instance.horizon,
                mode=mode
            )

        allocated_ids = {t.id for t, _ in new_assignments}
        unallocated_tasks = [t for t in unallocated_tasks if t.id not in allocated_ids]

        changed = True

    return sat_to_schedule

def compute_task_regrets(
    instance: Instance,
    sat_to_tasks_ids: Dict[int, List[int]],
    task_index: Dict[int, Task],
    mode: str = "flexibility",
) -> Dict[int, float]:
    """
    Calcule le regret des tâches standards non encore allouées.

    - 0 satellites possibles  -> regret = -1 (on s'en fiche)
    - 1 satellite possible    -> regret très grand (tâche critique)
    - 2+ satellites possibles -> regret = second_best_cost - best_cost
    """
    standard_users_set = set(instance.standard_users)

    already_assigned = {t_id for lst in sat_to_tasks_ids.values() for t_id in lst}

    standard_tasks = [
        t for t in instance.tasks
        if t.user_id in standard_users_set and t.id not in already_assigned
    ]

    task_regrets: Dict[int, float] = {}

    for task in standard_tasks:
        marginal_costs = []

        for sat in instance.satellites:
            current_ids = sat_to_tasks_ids.get(sat.id, [])
            mc = marginal_cost_of_task_on_satellite(
                instance=instance,
                task=task,
                sat=sat,
                sat_current_tasks_ids=current_ids,
                task_index=task_index,
                mode=mode,
            )
            if mc < inf:
                marginal_costs.append(mc)

        if len(marginal_costs) == 0:
            task_regrets[task.id] = -1.0
        elif len(marginal_costs) == 1:
            task_regrets[task.id] = 1e9
        else:
            marginal_costs.sort()
            best = marginal_costs[0]
            second_best = marginal_costs[1]
            regret = second_best - best
            task_regrets[task.id] = regret

    return task_regrets

def regret_based_ssi_auction(
    instance: Instance,
    mode: str = "flexibility"
) -> Dict[int, List[ScheduledTask]]:
    """
    Enchères séquentielles basées sur le regret.
    On calcule d'abord le regret de chaque tâche standard,
    puis on les traite dans l'ordre décroissant de regret.
    """
    sat_to_tasks_ids, sat_to_schedule = build_initial_schedules_for_auctions(instance, mode)
    task_index = build_task_index(instance)
    standard_users_set = set(instance.standard_users)

    all_scheduled_ids = set(t_id for lst in sat_to_tasks_ids.values() for t_id in lst)
    standard_tasks = [
        t for t in instance.tasks
        if t.user_id in standard_users_set and t.id not in all_scheduled_ids
    ]

    task_regrets = compute_task_regrets(instance, sat_to_tasks_ids, task_index, mode)

    standard_tasks_sorted = sorted(
        standard_tasks,
        key=lambda t: (-task_regrets.get(t.id, 0.0), task_priority(t, mode))
    )

    for task in standard_tasks_sorted:
        best_sat_id = None
        best_cost = inf

        for sat in instance.satellites:
            current_ids = sat_to_tasks_ids.get(sat.id, [])
            mc = marginal_cost_of_task_on_satellite(
                instance=instance,
                task=task,
                sat=sat,
                sat_current_tasks_ids=current_ids,
                task_index=task_index,
                mode=mode
            )
            if mc < best_cost:
                best_cost = mc
                best_sat_id = sat.id

        if best_sat_id is not None and best_cost < inf:
            sat_to_tasks_ids[best_sat_id].append(task.id)

            current_ids = sat_to_tasks_ids[best_sat_id]
            current_tasks = [task_index[t_id] for t_id in current_ids]
            sat_obj = instance.satellites[best_sat_id]

            sat_to_schedule[best_sat_id] = schedule_tasks_for_satellite(
                satellite=sat_obj,
                tasks=current_tasks,
                horizon=instance.horizon,
                mode=mode
            )

    return sat_to_schedule

