/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   init.c                                             :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: ccakir <ccakir@student.42.fr>              +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2026/04/29 22:43:11 by ccakir            #+#    #+#             */
/*   Updated: 2026/04/30 14:45:35 by ccakir           ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

#include "./philosophers.h"

int	init_table(t_table *table)
{
	int	i;

	table->philos = malloc(sizeof(t_philo) * table->philo_count);
	table->forks = malloc(sizeof(pthread_mutex_t) * table->philo_count);
	table->start_time = get_time();
	table->is_someone_dead = 0;
	if (!table->philos || !table->forks)
		return (1);
	pthread_mutex_init(&table->dead_mutex, NULL);
	pthread_mutex_init(&table->print_mutex, NULL);
	i = -1;
	while (++i < table->philo_count)
		pthread_mutex_init(&table->forks[i], NULL);
	i = -1;
	while (++i < table->philo_count)
	{
		table->philos[i].id = i + 1;
		table->philos[i].eat_count = 0;
		table->philos[i].last_eat_time = table->start_time;
		table->philos[i].table = table;
		pthread_mutex_init(&table->philos[i].philo_mutex, NULL);
	}
	return (0);
}
