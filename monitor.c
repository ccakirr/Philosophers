/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   monitor.c                                          :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: ccakir <ccakir@student.42.fr>              +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2026/04/30 00:51:38 by ccakir            #+#    #+#             */
/*   Updated: 2026/04/30 14:42:43 by ccakir           ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

#include "./philosophers.h"

void	make_is_someone_dead_one(t_table *table)
{
	pthread_mutex_lock(&table->dead_mutex);
	table->is_someone_dead = 1;
	pthread_mutex_unlock(&table->dead_mutex);
}

void	check_done(t_table *table)
{
	int	i;

	i = 0;
	while (i < table->philo_count)
	{
		pthread_mutex_lock(&table->philos[i].philo_mutex);
		if (table->philos[i].eat_count != table->must_eat)
		{
			pthread_mutex_unlock(&table->philos[i].philo_mutex);
			return ;
		}
		pthread_mutex_unlock(&table->philos[i].philo_mutex);
		i++;
	}
	make_is_someone_dead_one(table);
}

void	*monitor(void *arg)
{
	t_table	*table;
	int		i;
	long	last_eat;

	table = (t_table *)arg;
	while (1)
	{
		i = 0;
		while (i < table->philo_count)
		{
			pthread_mutex_lock(&table->philos[i].philo_mutex);
			last_eat = table->philos[i].last_eat_time;
			pthread_mutex_unlock(&table->philos[i].philo_mutex);
			if (get_time() - last_eat >= table->time_to_die)
			{
				make_is_someone_dead_one(table);
				print_action(&table->philos[i], "died");
				return (NULL);
			}
			i++;
		}
		check_done(table);
		if (is_dead(table))
			return (NULL);
	}
}
