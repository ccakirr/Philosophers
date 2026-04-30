/* ************************************************************************** */
/*                                                                            */
/*                                                        :::      ::::::::   */
/*   utils.c                                            :+:      :+:    :+:   */
/*                                                    +:+ +:+         +:+     */
/*   By: ccakir <ccakir@student.42.fr>              +#+  +:+       +#+        */
/*                                                +#+#+#+#+#+   +#+           */
/*   Created: 2026/04/29 23:14:27 by ccakir            #+#    #+#             */
/*   Updated: 2026/04/30 14:44:00 by ccakir           ###   ########.fr       */
/*                                                                            */
/* ************************************************************************** */

#include "./philosophers.h"

long	get_time(void)
{
	struct timeval	tv;
	long			sec;
	long			micro_sec;

	gettimeofday(&tv, NULL);
	sec = tv.tv_sec;
	micro_sec = tv.tv_usec;
	return ((sec * 1000) + (micro_sec / 1000));
}

void	ft_usleep(long ms)
{
	long	now;
	long	stop_until;

	now = get_time();
	stop_until = now + ms;
	while (get_time() < stop_until)
	{
		usleep(100);
	}
}

void	print_action(t_philo *philo, char *action)
{
	pthread_mutex_lock(&philo->table->print_mutex);
	printf("%ld %d %s\n", get_time(), philo->id, action);
	pthread_mutex_unlock(&philo->table->print_mutex);
}

void	eat(t_philo *philo)
{
	take_forks(philo);
	if (is_dead(philo->table))
	{
		put_forks(philo);
		return ;
	}
	pthread_mutex_lock(&philo->philo_mutex);
	philo->last_eat_time = get_time();
	philo->eat_count++;
	pthread_mutex_unlock(&philo->philo_mutex);
	print_action(philo, "eating");
	ft_usleep(philo->table->time_to_eat);
	put_forks(philo);
}

long	calc_think_time(t_philo *philo)
{
	long	think_time;

	pthread_mutex_lock(&philo->philo_mutex);
	think_time = (philo->last_eat_time + philo->table->time_to_die)
		- get_time();
	pthread_mutex_unlock(&philo->philo_mutex);
	return (think_time);
}
